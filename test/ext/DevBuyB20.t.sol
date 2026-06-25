// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IBerylPad} from "../../src/interfaces/IBerylPad.sol";
import {BerylPadUniv4EthDevBuy} from "../../src/extensions/BerylPadUniv4EthDevBuy.sol";
import {IBerylPadUniv4EthDevBuy} from "../../src/extensions/interfaces/IBerylPadUniv4EthDevBuy.sol";
import {BerylPadB20Harness} from "./Helpers.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// LP3b: prove the Univ4 ETH DevBuy extension works with a B20 token end-to-end.
/// deployToken with a DevBuy (0% supply earmark, ETH msgValue) → the factory
/// mints 100b B20 into the v4 pool, then the extension wraps the ETH and buys
/// the freshly-listed B20 *from that pool* via the UniversalRouter, delivering
/// it to the recipient. This exercises the swap-out receiver path (the recipient
/// and the extension both receive B20 under the default policy) and confirms the
/// Base Sepolia UniversalRouter is v4-aware. The DevBuy runs before the MEV
/// module is enabled (BerylPad.deployToken order), so PoolLocked does not apply.
/// Base Sepolia fork.
contract DevBuyB20Test is BerylPadB20Harness {
    address constant RECIPIENT = address(0xD00D);
    uint256 constant DEV_BUY_ETH = 0.01 ether;

    function _devBuyExtension(BerylPadUniv4EthDevBuy devBuy)
        internal
        pure
        returns (IBerylPad.ExtensionConfig[] memory ext)
    {
        // pairedToken == WETH, so pairedTokenPoolKey is unused: leave it default-zero.
        IBerylPadUniv4EthDevBuy.Univ4EthDevBuyExtensionData memory data;
        data.recipient = RECIPIENT;
        data.pairedTokenAmountOutMinimum = 0;

        ext = new IBerylPad.ExtensionConfig[](1);
        ext[0] = IBerylPad.ExtensionConfig({
            extension: address(devBuy),
            msgValue: DEV_BUY_ETH,
            extensionBps: 0,
            extensionData: abi.encode(data)
        });
    }

    function test_devbuy_buys_from_pool() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        require(UNIVERSAL_ROUTER.code.length > 0, "UniversalRouter absent on fork");

        Apparatus memory a = _deployApparatus();
        BerylPadUniv4EthDevBuy devBuy =
            new BerylPadUniv4EthDevBuy(address(a.factory), WETH, UNIVERSAL_ROUTER, PERMIT2);

        vm.prank(OWNER);
        a.factory.setExtension(address(devBuy), true);

        vm.deal(address(this), 1 ether);
        address token = a.factory.deployToken{value: DEV_BUY_ETH}(
            _baseCfg(a, bytes32(uint256(4)), "DevBuy B20", "DVB", _devBuyExtension(devBuy))
        );

        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "is B20");
        assertEq(IERC20Min(token).totalSupply(), TOKEN_SUPPLY, "100b minted");
        // recipient received B20 bought with ETH from the freshly-created pool
        assertGt(IERC20Min(token).balanceOf(RECIPIENT), 0, "recipient received dev-bought B20");
        // the extension forwarded everything it bought (holds no leftover token)
        assertEq(IERC20Min(token).balanceOf(address(devBuy)), 0, "extension holds no leftover");
        // the ETH was consumed by the buy (extension keeps no ETH)
        assertEq(address(devBuy).balance, 0, "extension holds no leftover ETH");
    }
}
