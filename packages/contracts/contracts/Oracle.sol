pragma solidity ^0.8.24;

import {BaseHooks} from "./Vendor/balancer-v3/vault/contracts/BaseHooks.sol";

import {IHooks} from "./Vendor/balancer-v3/interfaces/contracts/vault/IHooks.sol";
import {IVault} from "./Vendor/balancer-v3/interfaces/contracts/vault/IVault.sol";

import {VaultGuard} from "./Vendor/balancer-v3/vault/contracts/VaultGuard.sol";
import {HookFlags} from "./Vendor/balancer-v3/interfaces/contracts/vault/VaultTypes.sol";

contract Oracle is BaseHooks, VaultGuard {
    constructor(IVault vault) VaultGuard(vault) {}

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        return hookFlags;
    }
}
