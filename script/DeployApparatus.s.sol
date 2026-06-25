// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Clanker} from "../src/Clanker.sol";
import {ClankerFeeLocker} from "../src/ClankerFeeLocker.sol";
import {ClankerHookStaticFeeV2} from "../src/hooks/ClankerHookStaticFeeV2.sol";
import {ClankerPoolExtensionAllowlist} from "../src/hooks/ClankerPoolExtensionAllowlist.sol";
import {ClankerMevBlockDelay} from "../src/mev-modules/ClankerMevBlockDelay.sol";
import {ClankerLpLockerMultiple} from "../src/lp-lockers/ClankerLpLockerMultiple.sol";
import {B20PolicyOrchestrator} from "../src/periphery/B20PolicyOrchestrator.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// LP5a: stand up the Beryl launchpad apparatus (the shared, one-time platform
/// infrastructure the FE launch form points at) on a live chain. Deploys the
/// Clanker factory + a CREATE2-mined v4 hook + LP locker + MEV module + fee
/// locker + the Beryl policy orchestrator, wires them, and registers the locker
/// as a fee depositor. Logs every address for the FE `.env`.
///
/// THE USER runs this with their own funded key — I never hold one:
///   base-forge script script/DeployApparatus.s.sol:DeployApparatus \
///     --rpc-url <rpc> --broadcast --private-key $DEPLOYER_KEY
/// Dry-run (no broadcast) simulates and prints the addresses.
///
/// Defaults target Base Sepolia (84532); override the canonical addresses via env
/// for another chain. The hook is mined against the standard CREATE2 deployer
/// (0x4e59…), which is how forge scripts deploy `new X{salt}` — NOT the test-time
/// address(this) used by the e2e suite.
contract DeployApparatus is Script {
    // CREATE2 deployer used by forge `new X{salt}` in broadcast/scripts.
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    function run() external {
        // canonical addresses (Base Sepolia defaults; override per chain via env)
        address poolManager =
            vm.envOr("POOL_MANAGER", address(0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408));
        address positionManager =
            vm.envOr("POSITION_MANAGER", address(0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80));
        address permit2 = vm.envOr("PERMIT2", address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
        address weth = vm.envOr("WETH", address(0x4200000000000000000000000000000000000006));

        vm.startBroadcast();
        address owner = msg.sender; // the broadcasting deployer owns the apparatus

        Clanker factory = new Clanker(owner);
        ClankerFeeLocker feeLocker = new ClankerFeeLocker(owner);

        // mine + deploy the v4 hook (address low bits must equal the permission bitmap)
        ClankerPoolExtensionAllowlist allowlist = new ClankerPoolExtensionAllowlist(owner);
        bytes memory hookArgs = abi.encode(poolManager, address(factory), address(allowlist), weth);
        (address predicted, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, type(ClankerHookStaticFeeV2).creationCode, hookArgs);
        ClankerHookStaticFeeV2 hook =
            new ClankerHookStaticFeeV2{salt: salt}(poolManager, address(factory), address(allowlist), weth);
        require(address(hook) == predicted, "hook address mismatch");

        ClankerMevBlockDelay mev = new ClankerMevBlockDelay(2);
        ClankerLpLockerMultiple locker =
            new ClankerLpLockerMultiple(owner, address(factory), address(feeLocker), positionManager, permit2);

        // fee-path infra the orchestrator folds into every compliant allowlist so a
        // pool can never brick on the hook's unconditional fee sweep (LP6 FIND-001)
        address[] memory feePathInfra = new address[](5);
        feePathInfra[0] = poolManager;
        feePathInfra[1] = positionManager;
        feePathInfra[2] = address(hook);
        feePathInfra[3] = address(locker);
        feePathInfra[4] = address(feeLocker);
        B20PolicyOrchestrator orchestrator = new B20PolicyOrchestrator(owner, feePathInfra);

        // wire
        factory.setHook(address(hook), true);
        factory.setLocker(address(locker), address(hook), true);
        factory.setMevModule(address(mev), true);
        factory.setDeprecated(false);
        feeLocker.addDepositor(address(locker)); // else the 2nd swap's fee sweep reverts

        vm.stopBroadcast();

        console.log("== Beryl launchpad apparatus deployed ==");
        console.log("owner            ", owner);
        console.log("FACTORY          ", address(factory));
        console.log("HOOK             ", address(hook));
        console.log("LP_LOCKER        ", address(locker));
        console.log("MEV_MODULE       ", address(mev));
        console.log("FEE_LOCKER       ", address(feeLocker));
        console.log("POLICY_ORCHESTR  ", address(orchestrator));
        console.log("poolManager      ", poolManager);
        console.log("positionManager  ", positionManager);
        console.log("permit2          ", permit2);
        console.log("weth             ", weth);
    }
}
