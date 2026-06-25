// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clanker} from "../../src/Clanker.sol";
import {IClanker} from "../../src/interfaces/IClanker.sol";
import {ClankerHookStaticFeeV2} from "../../src/hooks/ClankerHookStaticFeeV2.sol";
import {ClankerPoolExtensionAllowlist} from "../../src/hooks/ClankerPoolExtensionAllowlist.sol";
import {IClankerHookStaticFee} from "../../src/hooks/interfaces/IClankerHookStaticFee.sol";
import {IClankerHookV2} from "../../src/hooks/interfaces/IClankerHookV2.sol";
import {ClankerMevBlockDelay} from "../../src/mev-modules/ClankerMevBlockDelay.sol";
import {ClankerLpLockerMultiple} from "../../src/lp-lockers/ClankerLpLockerMultiple.sol";
import {ClankerFeeLocker} from "../../src/ClankerFeeLocker.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// Shared harness for the forked Clanker→B20 e2e suite (LP2/LP3). Extracts the
/// full apparatus bring-up (factory + mined v4 hook + locker + feeLocker + MEV,
/// wired as OWNER) and a parameterized DeploymentConfig builder so each test
/// varies only its extensionConfigs. Base Sepolia fork; B20 precompile in-process.
///
/// Mining note: HookMiner mines against `address(this)` (the concrete test
/// contract that inherits this harness and executes `new Hook{salt}`), so the
/// CREATE2 deployer stays consistent across the inherited call.
abstract contract ClankerB20Harness is Test {
    // Base Sepolia (84532) v4 + canonical addresses
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104; // v4-aware, Base Sepolia
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant OWNER = address(0xA11CE);
    uint256 constant TOKEN_SUPPLY = 100_000_000_000 ether;

    int24 constant SPACING = 200;
    int24 constant START_TICK = -230400; // tickIfToken0IsClanker (multiple of 200)
    int24 constant TICK_UPPER = 887200;

    uint160 constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    struct Apparatus {
        Clanker factory;
        ClankerHookStaticFeeV2 hook;
        ClankerLpLockerMultiple locker;
        ClankerMevBlockDelay mev;
        ClankerFeeLocker feeLocker;
    }

    /// Skip cleanly when run without --fork-url (no v4 state on the in-process chain).
    function _v4Present() internal view returns (bool) {
        return POOL_MANAGER.code.length > 0 && POSITION_MANAGER.code.length > 0;
    }

    function _deployHook(address factory) internal returns (ClankerHookStaticFeeV2 hook) {
        ClankerPoolExtensionAllowlist allowlist = new ClankerPoolExtensionAllowlist(OWNER);
        bytes memory ctorArgs = abi.encode(POOL_MANAGER, factory, address(allowlist), WETH);
        (address predicted, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(ClankerHookStaticFeeV2).creationCode, ctorArgs);
        hook = new ClankerHookStaticFeeV2{salt: salt}(POOL_MANAGER, factory, address(allowlist), WETH);
        require(address(hook) == predicted, "hook addr mismatch");
    }

    /// Deploy the full apparatus and wire it as OWNER (hook + locker pairing + MEV).
    function _deployApparatus() internal returns (Apparatus memory a) {
        a.factory = new Clanker(OWNER);
        a.feeLocker = new ClankerFeeLocker(OWNER);
        a.hook = _deployHook(address(a.factory));
        a.mev = new ClankerMevBlockDelay(2);
        a.locker = new ClankerLpLockerMultiple(
            OWNER, address(a.factory), address(a.feeLocker), POSITION_MANAGER, PERMIT2
        );

        vm.startPrank(OWNER);
        a.factory.setHook(address(a.hook), true);
        a.factory.setLocker(address(a.locker), address(a.hook), true);
        a.factory.setMevModule(address(a.mev), true);
        a.factory.setDeprecated(false);
        // the LP locker stores collected fees in the fee locker; without this it
        // reverts Unauthorized() on the second swap's beforeSwap fee sweep.
        a.feeLocker.addDepositor(address(a.locker));
        vm.stopPrank();
    }

    /// Build a single-position, WETH-paired DeploymentConfig; callers pass their
    /// own extensionConfigs (empty for a vanilla launch).
    function _baseCfg(
        Apparatus memory a,
        bytes32 salt,
        string memory name,
        string memory symbol,
        IClanker.ExtensionConfig[] memory extensions
    ) internal view returns (IClanker.DeploymentConfig memory) {
        address[] memory admins = new address[](1);
        admins[0] = OWNER;
        address[] memory recips = new address[](1);
        recips[0] = OWNER;
        uint16[] memory rbps = new uint16[](1);
        rbps[0] = 10000;
        int24[] memory tl = new int24[](1);
        tl[0] = START_TICK;
        int24[] memory tu = new int24[](1);
        tu[0] = TICK_UPPER;
        uint16[] memory pbps = new uint16[](1);
        pbps[0] = 10000;

        bytes memory feeData =
            abi.encode(IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10000, pairedFee: 10000}));
        bytes memory poolData = abi.encode(
            IClankerHookV2.PoolInitializationData({extension: address(0), extensionData: "", feeData: feeData})
        );

        return IClanker.DeploymentConfig({
            tokenConfig: IClanker.TokenConfig({
                tokenAdmin: OWNER,
                name: name,
                symbol: symbol,
                salt: salt,
                image: "",
                metadata: "",
                context: "",
                originatingChainId: block.chainid
            }),
            poolConfig: IClanker.PoolConfig({
                hook: address(a.hook),
                pairedToken: WETH,
                tickIfToken0IsClanker: START_TICK,
                tickSpacing: SPACING,
                poolData: poolData
            }),
            lockerConfig: IClanker.LockerConfig({
                locker: address(a.locker),
                rewardAdmins: admins,
                rewardRecipients: recips,
                rewardBps: rbps,
                tickLower: tl,
                tickUpper: tu,
                positionBps: pbps,
                lockerData: ""
            }),
            mevModuleConfig: IClanker.MevModuleConfig({mevModule: address(a.mev), mevModuleData: ""}),
            extensionConfigs: extensions
        });
    }
}
