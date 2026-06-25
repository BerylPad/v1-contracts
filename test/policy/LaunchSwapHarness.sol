// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBerylPad} from "../../src/interfaces/IBerylPad.sol";
import {BerylPadB20Harness} from "../ext/Helpers.sol";
import {PolicyHarness} from "./Helpers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

/// LP4b/LP4c shared harness: launch a vanilla B20 through the BerylPad fork, then
/// perform a real post-launch v4 swap (WETH -> B20) via the UniversalRouter from
/// an arbitrary trader address. Combines BerylPadB20Harness (apparatus + config)
/// with PolicyHarness (registry + scope flips). The swap is the surface LP4
/// gates with policy: the take leg moves B20 PoolManager -> trader, so the
/// trader (receiver) and PoolManager (sender) face the transfer policies.
abstract contract LaunchSwapHarness is BerylPadB20Harness, PolicyHarness {
    /// Deploy the full apparatus + a vanilla (no-policy) B20 with no extensions.
    function _launchVanilla(bytes32 salt, string memory name, string memory symbol)
        internal
        returns (Apparatus memory a, address token, PoolKey memory key)
    {
        a = _deployApparatus();
        IBerylPad.ExtensionConfig[] memory none = new IBerylPad.ExtensionConfig[](0);
        token = a.factory.deployToken(_baseCfg(a, salt, name, symbol, none));
        key = _poolKeyFor(a, token);
    }

    /// Reconstruct the pool's PoolKey (BerylPadHookV2._initializePool): WETH < B20
    /// so currency0 = WETH, dynamic-fee flag, our tickSpacing + hook.
    function _poolKeyFor(Apparatus memory a, address token) internal pure returns (PoolKey memory) {
        (address c0, address c1) = WETH < token ? (WETH, token) : (token, WETH);
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: SPACING,
            hooks: IHooks(address(a.hook))
        });
    }

    /// Past the MEV block-delay window so a post-launch swap is not PoolLocked.
    function _rollPastMev() internal {
        vm.roll(block.number + 3);
    }

    /// Swap `amountIn` WETH for B20 as `trader` via the UniversalRouter; returns
    /// the B20 received. Reverts bubble up (used for policy-forbid negative paths).
    function _swapWethForB20(address trader, PoolKey memory key, address token, uint128 amountIn)
        internal
        returns (uint256 received)
    {
        deal(WETH, trader, amountIn);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bool wethIsToken0 = Currency.unwrap(key.currency0) == WETH;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: wethIsToken0,
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(WETH, uint256(amountIn)); // SETTLE_ALL (pay WETH)
        params[2] = abi.encode(token, uint256(0)); // TAKE_ALL (receive B20)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.startPrank(trader);
        IERC20(WETH).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, amountIn, uint48(block.timestamp + 1));
        uint256 before = IERC20(token).balanceOf(trader);
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 1);
        received = IERC20(token).balanceOf(trader) - before;
        vm.stopPrank();
    }

    /// Sell `amountIn` B20 for WETH as `trader` (the trader must already hold B20).
    /// Accrues B20-side LP fees in the pool — used by the audit PoC to reach the
    /// fee-collection path that transfers the B20 (locker -> feeLocker).
    function _swapB20ForWeth(address trader, PoolKey memory key, address token, uint128 amountIn)
        internal
        returns (uint256 received)
    {
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bool b20IsToken0 = Currency.unwrap(key.currency0) == token;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: b20IsToken0, // selling B20 (token1 normally) -> false
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(token, uint256(amountIn)); // SETTLE_ALL (pay B20)
        params[2] = abi.encode(WETH, uint256(0)); // TAKE_ALL (receive WETH)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.startPrank(trader);
        IERC20(token).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(token, UNIVERSAL_ROUTER, amountIn, uint48(block.timestamp + 1));
        uint256 before = IERC20(WETH).balanceOf(trader);
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 1);
        received = IERC20(WETH).balanceOf(trader) - before;
        vm.stopPrank();
    }

    /// Attempt the swap and return whether it succeeded (no assertion). Used to
    /// derive the minimal allowlist set by probing membership configurations.
    function _trySwap(address trader, PoolKey memory key, address token, uint128 amountIn)
        internal
        returns (bool ok)
    {
        deal(WETH, trader, amountIn);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bool wethIsToken0 = Currency.unwrap(key.currency0) == WETH;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: wethIsToken0,
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(WETH, uint256(amountIn));
        params[2] = abi.encode(token, uint256(0));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.startPrank(trader);
        IERC20(WETH).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, amountIn, uint48(block.timestamp + 1));
        try IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 1) {
            ok = true;
        } catch {
            ok = false;
        }
        vm.stopPrank();
    }

    /// Same swap, but assert it reverts (policy-denied trader). `expectedErr` of
    /// length 0 matches any revert; otherwise the exact revert bytes are required.
    function _swapExpectRevert(
        address trader,
        PoolKey memory key,
        address token,
        uint128 amountIn,
        bytes memory expectedErr
    ) internal {
        deal(WETH, trader, amountIn);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bool wethIsToken0 = Currency.unwrap(key.currency0) == WETH;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: wethIsToken0,
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(WETH, uint256(amountIn));
        params[2] = abi.encode(token, uint256(0));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        vm.startPrank(trader);
        IERC20(WETH).approve(PERMIT2, amountIn);
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, amountIn, uint48(block.timestamp + 1));
        if (expectedErr.length == 0) {
            vm.expectRevert();
        } else {
            vm.expectRevert(expectedErr);
        }
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 1);
        vm.stopPrank();
    }
}
