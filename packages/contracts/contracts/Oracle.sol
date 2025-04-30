pragma solidity ^0.8.24;

import {BaseHooks} from "./Vendor/balancer-v3/vault/contracts/BaseHooks.sol";

import {IHooks} from "./Vendor/balancer-v3/interfaces/contracts/vault/IHooks.sol";
import {IVault} from "./Vendor/balancer-v3/interfaces/contracts/vault/IVault.sol";

import {VaultGuard} from "./Vendor/balancer-v3/vault/contracts/VaultGuard.sol";
import {HookFlags, TokenConfig, LiquidityManagement, AfterSwapParams} from "./Vendor/balancer-v3/interfaces/contracts/vault/VaultTypes.sol";

import {BasePoolFactory} from "./Vendor/balancer-v3/pool-utils/contracts/BasePoolFactory.sol";

import {IOracle} from "./Interfaces/IOracle.sol";

contract Oracle is IOracle, BaseHooks, VaultGuard {
    // --- Registry ---
    address public pool;

    constructor(IVault vault) VaultGuard(vault) {}

    /// @inheritdoc IHooks
    function onRegister(
        address _factory,
        address _pool,
        TokenConfig[] memory _tokenConfig,
        LiquidityManagement calldata _liquidityManagement
    ) public override onlyVault returns (bool) {
        if (pool != address(0)) {
            revert Oracle_AlreadyRegistered();
        }
        pool = _pool;

        // Check if pool was created by the allowed factory.
        if (!BasePoolFactory(_factory).isPoolFromFactory(_pool)) {
            revert Oracle_PoolNotFromFactory(_pool);
        }
        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        return hookFlags;
    }

    function onAfterSwap(
        AfterSwapParams calldata params_
    ) public override onlyVault returns (bool, uint256) {
        return (true, 0);
    }
}
