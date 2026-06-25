// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBerylPad} from "../interfaces/IBerylPad.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";

/// @notice BerylPad Token Launcher — B20-precompile variant (Beryl fork).
/// @dev Forked from clanker-devco/v4-contracts (MIT). Replaces the constructor-mint
///      `new BerylPadToken{salt}(...)` with a `createB20` precompile call plus an
///      initCalls `batchMint` that lands the FULL supply on the factory.
///
///      WHY mint-to-factory works: this is an `external library` function, so it is
///      DELEGATECALL'd by the BerylPad factory — `address(this)` and the createB20
///      caller therefore resolve to the factory, and the bootstrap window bypasses
///      role gates (no MINT_ROLE grant needed). A fresh ASSET's default supply cap
///      admits the 100b mint. All of this is proven in `test/MintToFactory.t.sol`
///      (LP2a). The factory then approve+transferFrom-distributes the supply to the
///      LP locker and extensions exactly as upstream Clanker does.
///
///      Clanker's image/metadata/context strings have no native B20 slot; Beryl
///      indexes B20 metadata off-chain, so they are intentionally not threaded here.
library BerylPadDeployer {
    function deployToken(IBerylPad.TokenConfig memory tokenConfig, uint256 supply)
        external
        returns (address tokenAddress)
    {
        // Preserve Clanker's salt semantics; the B20 factory additionally keys on
        // (variant, sender) internally, so the derived address differs from the old
        // CREATE2 result — downstream ordering reads the returned address, so this is fine.
        bytes32 salt = keccak256(abi.encode(tokenConfig.tokenAdmin, tokenConfig.salt));

        bytes memory params = B20FactoryLib.encodeAssetCreateParams(
            tokenConfig.name,
            tokenConfig.symbol,
            tokenConfig.tokenAdmin, // DEFAULT_ADMIN_ROLE holder (Clanker's tokenAdmin)
            18 // Clanker's implicit OZ ERC20 decimals; within ASSET's [6,18] range
        );

        // Replicate BerylPadToken's originating-chain-only mint: full supply on the
        // originating chain, zero elsewhere (preserves deployTokenZeroSupply semantics).
        bytes[] memory initCalls;
        if (block.chainid == tokenConfig.originatingChainId) {
            address[] memory recipients = new address[](1);
            recipients[0] = address(this); // the factory (delegatecall context)
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = supply;
            initCalls = new bytes[](1);
            initCalls[0] = B20FactoryLib.encodeBatchMint(recipients, amounts);
        } else {
            initCalls = new bytes[](0); // non-originating chain → zero supply
        }

        tokenAddress = StdPrecompiles.B20_FACTORY.createB20(
            IB20Factory.B20Variant.ASSET,
            salt,
            params,
            initCalls
        );
    }
}
