// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BerylPadHookV2} from "./BerylPadHookV2.sol";
import {IBerylPadHookStaticFee} from "./interfaces/IBerylPadHookStaticFee.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract BerylPadHookStaticFeeV2 is BerylPadHookV2, IBerylPadHookStaticFee {
    mapping(PoolId => uint24) public berylPadFee;
    mapping(PoolId => uint24) public pairedFee;

    constructor(
        address _poolManager,
        address _factory,
        address _poolExtensionAllowlist,
        address _weth
    ) BerylPadHookV2(_poolManager, _factory, _poolExtensionAllowlist, _weth) {}

    function _initializeFeeData(PoolKey memory poolKey, bytes memory feeData) internal override {
        PoolStaticConfigVars memory _poolConfigVars = abi.decode(feeData, (PoolStaticConfigVars));

        if (_poolConfigVars.berylPadFee > MAX_LP_FEE) {
            revert BerylPadFeeTooHigh();
        }

        if (_poolConfigVars.pairedFee > MAX_LP_FEE) {
            revert PairedFeeTooHigh();
        }

        berylPadFee[poolKey.toId()] = _poolConfigVars.berylPadFee;
        pairedFee[poolKey.toId()] = _poolConfigVars.pairedFee;

        emit PoolInitialized(poolKey.toId(), _poolConfigVars.berylPadFee, _poolConfigVars.pairedFee);
    }

    // set the LP fee according to the berylPad/paired fee configuration
    function _setFee(PoolKey calldata poolKey, IPoolManager.SwapParams calldata swapParams)
        internal
        override
    {
        uint24 fee = swapParams.zeroForOne != berylPadIsToken0[poolKey.toId()]
            ? pairedFee[poolKey.toId()]
            : berylPadFee[poolKey.toId()];

        _setProtocolFee(fee);
        IPoolManager(poolManager).updateDynamicLPFee(poolKey, fee);
    }
}
