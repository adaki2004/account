// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Base.t.sol";

/// @dev Mock xERC20 token for testing
contract MockXERC20 {
    string public name = "Test xERC20";
    string public symbol = "XERC";

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event XTransfer(uint256 indexed chain, address indexed to, uint256 value);

    constructor() {
        // Mint some tokens to test addresses
        balanceOf[address(this)] = 1000000 * 10**18;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function xTransfer(uint256 chain, address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance for xTransfer");
        balanceOf[msg.sender] -= value;
        emit XTransfer(chain, to, value);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

/// @dev Test contract to debug xTransfer via Porto AA
contract XTransferDebugTest is BaseTest {
    MockXERC20 xtoken;
    address dani;
    uint256 daniKey;
    address bob;

    function setUp() public override {
        super.setUp();

        // Create test accounts
        daniKey = 0xdead;
        dani = vm.addr(daniKey);
        bob = address(0xb0b);

        // Deploy mock xERC20
        xtoken = new MockXERC20();

        // Mint tokens to Dani
        xtoken.mint(dani, 1000 * 10**18);

        // Set up EIP-7702 delegation for Dani
        _setEIP7702Delegation(dani);

        console.log("Setup complete:");
        console.log("  Dani:", dani);
        console.log("  Dani balance:", xtoken.balanceOf(dani));
        console.log("  Bob:", bob);
        console.log("  xToken:", address(xtoken));
        console.log("  Orchestrator:", address(oc));
        console.log("  Account impl:", address(account));
    }

    /// @dev Test 1: Direct xTransfer call from Dani (no AA)
    function test_DirectXTransfer() public {
        console.log("\n=== Test 1: Direct xTransfer ===");

        uint256 amount = 100 * 10**18;
        uint256 targetChain = 167010; // L2A chain ID

        vm.prank(dani);
        bool success = xtoken.xTransfer(targetChain, bob, amount);

        assertTrue(success, "xTransfer should succeed");
        assertEq(xtoken.balanceOf(dani), 900 * 10**18, "Dani balance should decrease");
        console.log("  Direct xTransfer succeeded!");
    }

    /// @dev Test 2: xTransfer via delegated account with execute()
    function test_XTransferViaDelegatedAccount() public {
        console.log("\n=== Test 2: xTransfer via Delegated Account ===");

        uint256 amount = 100 * 10**18;
        uint256 targetChain = 167010;

        // Build xTransfer call
        bytes memory xTransferData = abi.encodeWithSignature(
            "xTransfer(uint256,address,uint256)",
            targetChain,
            bob,
            amount
        );

        console.log("  xTransfer calldata length:", xTransferData.length);
        console.logBytes(xTransferData);

        // Build ERC7579 execution (single call)
        ERC7821.Call[] memory calls = new ERC7821.Call[](1);
        calls[0] = ERC7821.Call({
            to: address(xtoken),
            value: 0,
            data: xTransferData
        });

        bytes memory executionData = abi.encode(calls);
        console.log("  ExecutionData length:", executionData.length);

        // Execute via delegated account directly (bypass Orchestrator for now)
        // This simulates what Orchestrator does when calling the EOA
        // Convert executionData to calldata-compatible format
        // We can't use reencodeBatchAsExecuteCalldata directly, so encode manually
        bytes memory executeCalldata = abi.encodeWithSelector(
            ERC7821.execute.selector,
            _ERC7821_BATCH_EXECUTION_MODE,
            executionData,
            abi.encode(bytes32(0)) // opData with keyHash = 0
        );

        console.log("  Execute calldata length:", executeCalldata.length);
        console.log("  Calling delegated account at:", dani);
        console.log("  Dani code length:", dani.code.length);
        console.logBytes(dani.code);

        // Call the delegated account
        vm.prank(address(oc)); // Orchestrator is the caller
        (bool success, bytes memory result) = dani.call(executeCalldata);

        if (!success) {
            console.log("  Call failed!");
            console.log("  Result length:", result.length);
            if (result.length > 0) {
                console.log("  Error:");
                console.logBytes(result);

                // Try to decode common errors
                if (result.length >= 4) {
                    bytes4 errorSig = bytes4(result);
                    console.log("  Error signature:");
                    console.logBytes4(errorSig);
                }
            }
            revert("Delegated account call failed");
        }

        console.log("  Call succeeded!");
        assertEq(xtoken.balanceOf(dani), 900 * 10**18, "Dani balance should decrease");
    }

    /// @dev Test 3: Full flow via Orchestrator.execute()
    function test_XTransferViaOrchestrator() public {
        console.log("\n=== Test 3: xTransfer via Orchestrator ===");

        uint256 amount = 100 * 10**18;
        uint256 targetChain = 167010;

        // Build xTransfer call
        bytes memory xTransferData = abi.encodeWithSignature(
            "xTransfer(uint256,address,uint256)",
            targetChain,
            bob,
            amount
        );

        // Build ERC7579 execution
        ERC7821.Call[] memory calls = new ERC7821.Call[](1);
        calls[0] = ERC7821.Call({
            to: address(xtoken),
            value: 0,
            data: xTransferData
        });

        bytes memory executionData = abi.encode(calls);

        // Build Intent
        ICommon.Intent memory intent = ICommon.Intent({
            eoa: dani,
            executionData: executionData,
            nonce: 0,
            payer: address(0), // Defaults to eoa
            paymentToken: address(0),
            paymentMaxAmount: 1 ether,
            combinedGas: 2_000_000,
            encodedPreCalls: new bytes[](0),
            encodedFundTransfers: new bytes[](0),
            settler: address(0),
            expiry: 0,
            isMultichain: false,
            funder: address(0),
            funderSignature: "",
            settlerContext: "",
            paymentAmount: 0,
            paymentRecipient: address(0),
            signature: "", // Empty - signature check is bypassed in IthacaAccount
            paymentSignature: "",
            supportedAccountImplementation: address(0)
        });

        bytes memory encodedIntent = abi.encode(intent);
        console.log("  Intent encoded, length:", encodedIntent.length);

        // Execute via Orchestrator
        console.log("  Calling Orchestrator.execute()...");
        bytes4 err = oc.execute(encodedIntent);

        if (err != bytes4(0)) {
            console.log("  Orchestrator returned error:");
            console.logBytes4(err);

            // Decode known errors
            if (err == Orchestrator.CallError.selector) {
                console.log("  Error: CallError() - The call to the EOA failed");
            } else if (err == Orchestrator.VerificationError.selector) {
                console.log("  Error: VerificationError() - Signature verification failed");
            } else if (err == Orchestrator.PaymentError.selector) {
                console.log("  Error: PaymentError() - Payment failed");
            } else if (err == Orchestrator.InsufficientGas.selector) {
                console.log("  Error: InsufficientGas() - Not enough gas provided");
            }

            revert("Orchestrator.execute() failed");
        }

        console.log("  Orchestrator.execute() succeeded!");
        assertEq(xtoken.balanceOf(dani), 900 * 10**18, "Dani balance should decrease");
    }

    /// @dev Test 4: Check if delegation is working
    function test_DelegationCheck() public {
        console.log("\n=== Test 4: Delegation Check ===");

        console.log("  Dani address:", dani);
        console.log("  Dani code length:", dani.code.length);
        console.log("  Dani code:");
        console.logBytes(dani.code);

        // Check if code starts with 0xef0100
        bytes memory code = dani.code;
        require(code.length >= 3, "Code too short");
        require(code[0] == 0xef, "Missing delegation prefix 0xef");
        require(code[1] == 0x01, "Missing delegation prefix 0x01");
        require(code[2] == 0x00, "Missing delegation prefix 0x00");

        // Extract delegated address
        address delegatedImpl = address(uint160(bytes20(code)));
        console.log("  Delegated implementation:", delegatedImpl);
        console.log("  Expected implementation:", address(account));

        assertEq(delegatedImpl, address(account), "Delegation should point to account implementation");
        console.log("  Delegation is correct!");
    }
}
