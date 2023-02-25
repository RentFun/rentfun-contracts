// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

contract Enum {
    /// @notice rent status
    /// @dev RENTED can still be RENTABLE if the endTime is expired
    /// @dev UNRENTABLE means no more rental but can still be rented as the last rental may not expire.
    enum RentStatus {NONE, RENTABLE, RENTED, UNRENTABLE}
}