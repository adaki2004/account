// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

error EmptyStack();

/// @notice A minimal bytes32 stack implementation in regular storage (non-transient).
library LibStack {
    /// @dev Helper struct to store the base slot of the stack.
    struct Stack {
        uint256 slot;
    }

    function stack(uint256 slot) internal pure returns (Stack memory s) {
        s.slot = slot;
    }

    /// @dev Returns the top-most value of the stack.
    /// Throws an `EmptyStack()` error if the stack is empty.
    function top(Stack memory s) internal view returns (bytes32 val) {
        uint256 slot = s.slot;

        assembly ("memory-safe") {
            let len := sload(slot)
            if iszero(len) {
                mstore(0x00, 0xbc7ec779) // `EmptyStack()`
                revert(0x1c, 0x04)
            }

            val := sload(add(slot, len))
        }
    }

    /// @dev Returns the size of the stack.
    function size(Stack memory s) internal view returns (uint256 len) {
        uint256 slot = s.slot;

        assembly ("memory-safe") {
            len := sload(slot)
        }
    }

    /// @dev Pushes a bytes32 value to the top of the stack.
    function push(Stack memory s, bytes32 val) internal {
        uint256 slot = s.slot;

        assembly ("memory-safe") {
            let len := add(sload(slot), 1)
            sstore(add(slot, len), val)
            sstore(slot, len)
        }
    }

    /// @dev Pops the top-most value from the stack.
    /// Throws an `EmptyStack()` error if the stack is empty.
    /// @dev Cleans the value on top of the stack to save gas on future writes.
    function pop(Stack memory s) internal {
        uint256 slot = s.slot;

        assembly ("memory-safe") {
            let len := sload(slot)
            if iszero(len) {
                mstore(0x00, 0xbc7ec779) // `EmptyStack()`
                revert(0x1c, 0x04)
            }

            sstore(add(slot, len), 0) // Clean the popped value
            sstore(slot, sub(len, 1))
        }
    }
}
