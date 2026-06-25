// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BerylPad} from "../src/BerylPad.sol";
import {IBerylPad} from "../src/interfaces/IBerylPad.sol";
import {IBerylPadHookStaticFee} from "../src/hooks/interfaces/IBerylPadHookStaticFee.sol";
import {IBerylPadHookV2} from "../src/hooks/interfaces/IBerylPadHookV2.sol";

/// Launch one B20 through the deployed apparatus factory: `deployToken` runs
/// createB20 (full 100b supply to the factory) + v4 pool init + LP placement, in
/// one tx. Vanilla — no policy, no extensions. Reads the apparatus addresses from
/// env (printed by DeployApparatus). THE USER's funded key broadcasts.
///
///   FACTORY=0x.. HOOK=0x.. LP_LOCKER=0x.. MEV_MODULE=0x.. \
///   base-forge script script/LaunchToken.s.sol:LaunchToken \
///     --rpc-url <rpc> --broadcast --private-key $KEY
///
/// Mirrors the e2e harness `_baseCfg` exactly (single full-reward position to the
/// launcher, WETH-paired, static 1% fees, START_TICK -230400 / spacing 200).
contract LaunchToken is Script {
    int24 constant START_TICK = -230400; // tickIfToken0IsBerylPad (multiple of spacing)
    int24 constant TICK_UPPER = 887200;
    int24 constant SPACING = 200;

    function run() external {
        address factory = vm.envAddress("FACTORY");
        address hook = vm.envAddress("HOOK");
        address locker = vm.envAddress("LP_LOCKER");
        address mev = vm.envAddress("MEV_MODULE");
        address weth = vm.envOr("WETH", address(0x4200000000000000000000000000000000000006));
        string memory name = vm.envOr("TOKEN_NAME", string("Beryl Live Test"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("BLT"));

        vm.startBroadcast();
        address admin = msg.sender; // launcher = token admin = reward recipient

        address[] memory admins = new address[](1);
        admins[0] = admin;
        address[] memory recips = new address[](1);
        recips[0] = admin;
        uint16[] memory rbps = new uint16[](1);
        rbps[0] = 10000;
        int24[] memory tl = new int24[](1);
        tl[0] = START_TICK;
        int24[] memory tu = new int24[](1);
        tu[0] = TICK_UPPER;
        uint16[] memory pbps = new uint16[](1);
        pbps[0] = 10000;

        bytes memory feeData =
            abi.encode(IBerylPadHookStaticFee.PoolStaticConfigVars({berylPadFee: 10000, pairedFee: 10000}));
        bytes memory poolData = abi.encode(
            IBerylPadHookV2.PoolInitializationData({extension: address(0), extensionData: "", feeData: feeData})
        );

        IBerylPad.DeploymentConfig memory cfg = IBerylPad.DeploymentConfig({
            tokenConfig: IBerylPad.TokenConfig({
                tokenAdmin: admin,
                name: name,
                symbol: symbol,
                salt: bytes32(uint256(block.timestamp)), // unique per run (avoids createB20 collision)
                image: "",
                metadata: "",
                context: "",
                originatingChainId: block.chainid
            }),
            poolConfig: IBerylPad.PoolConfig({
                hook: hook,
                pairedToken: weth,
                tickIfToken0IsBerylPad: START_TICK,
                tickSpacing: SPACING,
                poolData: poolData
            }),
            lockerConfig: IBerylPad.LockerConfig({
                locker: locker,
                rewardAdmins: admins,
                rewardRecipients: recips,
                rewardBps: rbps,
                tickLower: tl,
                tickUpper: tu,
                positionBps: pbps,
                lockerData: ""
            }),
            mevModuleConfig: IBerylPad.MevModuleConfig({mevModule: mev, mevModuleData: ""}),
            extensionConfigs: new IBerylPad.ExtensionConfig[](0)
        });

        address token = BerylPad(factory).deployToken(cfg);
        vm.stopBroadcast();

        console.log("== B20 launched ==");
        console.log("B20_TOKEN ", token);
        console.log("admin     ", admin);
        console.log("name/symbol", name, symbol);
    }
}
