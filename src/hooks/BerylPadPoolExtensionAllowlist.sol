// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBerylPadPoolExtensionAllowlist} from "./interfaces/IBerylPadPoolExtensionAllowlist.sol";

import {OwnerAdmins} from "../utils/OwnerAdmins.sol";

contract BerylPadPoolExtensionAllowlist is IBerylPadPoolExtensionAllowlist, OwnerAdmins {
    mapping(address extension => bool enabled) public enabledExtensions;

    constructor(address owner_) OwnerAdmins(owner_) {}

    function setPoolExtension(address extension, bool enabled) external onlyOwnerOrAdmin {
        enabledExtensions[extension] = enabled;
        emit SetPoolExtension(extension, enabled);
    }
}
