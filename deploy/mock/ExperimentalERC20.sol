// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract ExperimentERC20 is ERC20, Ownable {
    address payable private constant _GWYNETH_EXTENSION_ORACLE =
        payable(0x1ADB9959EB142bE128E6dfEcc8D571f07cd66DeE);

    string internal _name;
    string internal _symbol;
    uint256 internal _scalar;
    uint256 internal _mintCap;

    constructor(string memory name_, string memory symbol_, uint256 scalar_) {
        _name = name_;
        _symbol = symbol_;
        _scalar = scalar_;
        _mintCap = type(uint128).max;
        _initializeOwner(msg.sender);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function setMintCap(uint256 mintCap) public virtual onlyOwner {
        _mintCap = mintCap;
    }

    function mint(address recipient, uint256 value) public virtual {
        require(value < _mintCap, "Mint cap exceeded");
        _mint(recipient, value);
    }

    function swap(address target, address recipient, uint256 amount) public virtual {
        _burn(msg.sender, amount);
        ExperimentERC20(payable(target)).mint(recipient, (amount * _scalar) / 1 ether);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return super.transfer(to, amount);
    }

    /// @notice Gwyneth ExtensionOracle entrypoint used for L1→L2 “ultrablock” forwarded calls.
    function gwynethForwarder() external payable {
        require(
            msg.sender == _GWYNETH_EXTENSION_ORACLE,
            "ExperimentERC20: gwynethForwarder not from ExtensionOracle"
        );

        assembly {
            let cds := calldatasize()
            // strip 4 (selector) + 32 (address)
            let len := sub(cds, 36)

            // copy calldata[4..cds-32] -> mem[0..len]
            calldatacopy(0, 4, len)

            // load address = last 32 bytes, low 20 bytes
            let pos := sub(cds, 32)
            let addr := and(calldataload(pos), 0xffffffffffffffffffffffffffffffffffffffff)

            // delegatecall(gas, addr, 0, len, 0, 0)
            let ok := delegatecall(gas(), addr, 0, len, 0, 0)
            let rds := returndatasize()
            returndatacopy(0, 0, rds)
            switch ok
            case 0 { revert(0, rds) }
            default { return(0, rds) }
        }
    }

    fallback() external payable {}
    receive() external payable {}
}
