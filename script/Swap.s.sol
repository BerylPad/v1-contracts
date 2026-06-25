// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
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

interface IWETH9 {
    function deposit() external payable;
}

/// Trigger a live BUY (WETH->B20) then SELL (B20->WETH) on the launched pool via
/// the v4-aware UniversalRouter. Unlike the e2e harness this wraps real ETH->WETH
/// (no test `deal`) and uses live Permit2 approvals. Run AFTER the MEV block-delay
/// window (a few blocks past the launch tx). THE USER's funded key broadcasts.
///
///   B20_TOKEN=0x.. HOOK=0x.. [BUY_IN_WEI=5000000000000000] \
///   base-forge script script/Swap.s.sol:Swap --rpc-url <rpc> --broadcast --private-key $KEY
contract Swap is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104; // v4-aware, Base Sepolia
    int24 constant SPACING = 200;

    function run() external {
        address token = vm.envAddress("B20_TOKEN");
        address hook = vm.envAddress("HOOK");
        address weth = vm.envOr("WETH", address(0x4200000000000000000000000000000000000006));
        uint128 buyIn = uint128(vm.envOr("BUY_IN_WEI", uint256(0.005 ether)));

        PoolKey memory key = _poolKey(token, weth, hook);

        vm.startBroadcast();
        // Wrap ETH -> WETH to fund the buy leg (live chain: no test deal()).
        IWETH9(weth).deposit{value: buyIn}();

        uint256 got = _buy(key, token, weth, buyIn);
        console.log("BUY  WETH->B20, received B20:", got);

        uint128 sellIn = uint128(got / 2); // sell half back -> accrues B20-side LP fee
        uint256 back = _sell(key, token, weth, sellIn);
        console.log("SELL B20->WETH, received WETH:", back);
        vm.stopBroadcast();

        console.log("== swap round-trip done ==");
    }

    function _poolKey(address token, address weth, address hook) internal pure returns (PoolKey memory) {
        (address c0, address c1) = weth < token ? (weth, token) : (token, weth);
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: SPACING,
            hooks: IHooks(hook)
        });
    }

    function _buy(PoolKey memory key, address token, address weth, uint128 amtIn)
        internal
        returns (uint256 received)
    {
        IERC20(weth).approve(PERMIT2, amtIn);
        IPermit2(PERMIT2).approve(weth, UNIVERSAL_ROUTER, amtIn, uint48(block.timestamp + 3600));

        bool wethIsToken0 = Currency.unwrap(key.currency0) == weth;
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: wethIsToken0,
                amountIn: amtIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(weth, uint256(amtIn)); // SETTLE_ALL (pay WETH)
        params[2] = abi.encode(token, uint256(0)); // TAKE_ALL (receive B20)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        uint256 before = IERC20(token).balanceOf(msg.sender);
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60);
        received = IERC20(token).balanceOf(msg.sender) - before;
    }

    function _sell(PoolKey memory key, address token, address weth, uint128 amtIn)
        internal
        returns (uint256 received)
    {
        IERC20(token).approve(PERMIT2, amtIn);
        IPermit2(PERMIT2).approve(token, UNIVERSAL_ROUTER, amtIn, uint48(block.timestamp + 3600));

        bool b20IsToken0 = Currency.unwrap(key.currency0) == token;
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: b20IsToken0,
                amountIn: amtIn,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(token, uint256(amtIn)); // SETTLE_ALL (pay B20)
        params[2] = abi.encode(weth, uint256(0)); // TAKE_ALL (receive WETH)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        uint256 before = IERC20(weth).balanceOf(msg.sender);
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60);
        received = IERC20(weth).balanceOf(msg.sender) - before;
    }
}
