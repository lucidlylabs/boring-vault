// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

contract CreateDnEnaPtHedgeLeafsScript is Script, MerkleTreeHelper {
    address public constant TODO_ADDRESS = address(0);
    // Fill these after the vaults/contracts are deployed and API calldata is verified.
    address public ethPtVault = 0x3A140976d40d4fd23579dE5BaDFE59a78a94e168;
    address public hyperEvmHedgeVault = 0x3A140976d40d4fd23579dE5BaDFE59a78a94e168;
    address public ethRawDataDecoderAndSanitizer = 0x02649C96083c61C5419e3b3516fEDC0f5E8115C2;
    address public hyperEvmRawDataDecoderAndSanitizer = 0xD834860459a89e609243f00C6fcb4861B351583f;
    address public ethManagerAddress = 0xD29E5c69D11c826f36e40eB70f9Ee01BdC282E6A;
    address public hyperEvmManagerAddress = 0xD29E5c69D11c826f36e40eB70f9Ee01BdC282E6A;
    address public ethAccountantAddress = 0x962590Ec3F666e8b5CCCF599cc01335c4F561211;
    address public hyperEvmAccountantAddress = 0x962590Ec3F666e8b5CCCF599cc01335c4F561211;
    address public strategist = 0x0c6DD78B1507bbae4781ee8aed9ba529f7c0E4E3;
    address public ena = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address public sEna = 0x8bE3460A480c80728a8C4D7a5D5303c85ba7B3b9;
    address public sySena = 0xA36ECCA8B7624D224F01CD6649C8afAd3Da12C3D;
    address public ptSena = 0xb9b3a5823DfDb39389F50742eE7bB81CF0BE56cB;
    address public ytSena = 0xd29025e0665774f66355656732cBeC826d4425ab;
    address public ptSenaMarket = 0xf1e067f8334a5A21dA018A15E29CB78252190A1b;
    uint32 public enaPerpAssetId = 122;
    uint64 public ccipHyperEvmDestinationSelector = 2442541497099098535;

    function run() external {
        generateEthereumLeafs();
        generateHyperEvmLeafs();
    }

    function generateEthereumLeafs() public {
        leafIndex = type(uint256).max;
        setSourceChainName(mainnet);
        vm.createSelectFork(sourceChain);
        _setCommonMainnetAddresses();

        ManageLeaf[] memory leafs = new ManageLeaf[](256);

        address ethUsdc = getAddress(sourceChain, "USDC");
        _addCcipLeafs(leafs, ethUsdc);

        address[] memory flyTradeTokens = new address[](2);
        flyTradeTokens[0] = ethUsdc;
        flyTradeTokens[1] = ena;
        SwapKind[] memory flyTradeKinds = new SwapKind[](2);
        flyTradeKinds[0] = SwapKind.BuyAndSell;
        flyTradeKinds[1] = SwapKind.BuyAndSell;
        _addMagpieSwapLeafs(leafs, flyTradeTokens, flyTradeKinds);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ena,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve sENA to spend ENA",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = sEna;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "mint(uint256,address)",
            new address[](1),
            "Mint sENA to Ethereum PT vault",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;

        _addPendlePtSenaLeafs(leafs);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        _generateLeafs("./leafs/Mainnet/DnPtSenaLeafs.json", leafs, manageTree[manageTree.length - 1][0], manageTree);
    }

    function generateHyperEvmLeafs() public {
        leafIndex = type(uint256).max;
        setSourceChainName(hyperevm);
        vm.createSelectFork(sourceChain);
        _setCommonHyperEvmAddresses();

        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addCoreWriterUsdcDepositLeafs(leafs);

        uint32[] memory perpAssets = new uint32[](1);
        perpAssets[0] = enaPerpAssetId;
        _addCoreWriterLimitOrderLeafs(leafs, perpAssets);
        _addCoreWriterUsdClassTransferLeafs(leafs);

        address[] memory destinations = new address[](1);
        destinations[0] = hyperEvmHedgeVault;
        address[] memory subAccounts = new address[](1);
        subAccounts[0] = address(0);
        _addCoreWriterSendAssetLeafs(leafs, destinations, subAccounts);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        _generateLeafs("./leafs/HyperEvm/DnPtSenaLeafs.json", leafs, manageTree[manageTree.length - 1][0], manageTree);
    }

    function _setCommonMainnetAddresses() internal {
        setAddress(true, mainnet, "boringVault", ethPtVault);
        setAddress(true, mainnet, "managerAddress", ethManagerAddress);
        setAddress(true, mainnet, "accountantAddress", ethAccountantAddress);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", ethRawDataDecoderAndSanitizer);
    }

    function _setCommonHyperEvmAddresses() internal {
        setAddress(true, hyperevm, "boringVault", hyperEvmHedgeVault);
        setAddress(true, hyperevm, "managerAddress", hyperEvmManagerAddress);
        setAddress(true, hyperevm, "accountantAddress", hyperEvmAccountantAddress);
        setAddress(true, hyperevm, "rawDataDecoderAndSanitizer", hyperEvmRawDataDecoderAndSanitizer);
    }

    function _addCcipLeafs(ManageLeaf[] memory leafs, address ethUsdc) internal {
        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ethUsdc,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve CCIP router to spend Ethereum USDC",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = getAddress(sourceChain, "ccipRouter");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            getAddress(sourceChain, "ccipRouter"),
            true,
            "ccipSend(uint64,(bytes,bytes,(address,uint256)[],address,bytes))",
            new address[](4),
            "Bridge Ethereum USDC to HyperEVM hedge vault using CCIP",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = address(uint160(ccipHyperEvmDestinationSelector));
        leafs[leafIndex].argumentAddresses[1] = hyperEvmHedgeVault;
        leafs[leafIndex].argumentAddresses[2] = ethUsdc;
        leafs[leafIndex].argumentAddresses[3] = address(0);
    }

    function _addPendlePtSenaLeafs(ManageLeaf[] memory leafs) internal {
        address pendleRouter = getAddress(sourceChain, "pendleRouter");
        address decoderAndSanitizer = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve Pendle router to spend sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = pendleRouter;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "swapExactTokenForPt(address,address,uint256,(uint256,uint256,uint256,uint256,uint256),(address,uint256,address,address,(uint8,address,bytes,bool)),(address,uint256,((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],bytes))",
            new address[](7),
            "Swap sENA for PT-sENA via Pendle API route",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = ptSenaMarket;
        leafs[leafIndex].argumentAddresses[2] = sEna;
        leafs[leafIndex].argumentAddresses[3] = sEna;
        leafs[leafIndex].argumentAddresses[4] = address(0);
        leafs[leafIndex].argumentAddresses[5] = address(0);
        leafs[leafIndex].argumentAddresses[6] = address(0);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ptSena,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve Pendle router to spend PT-sENA-24SEP2026",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = pendleRouter;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemPyToSy(address,address,uint256,uint256)",
            new address[](2),
            "Burn PT-sENA-24SEP2026 and YT-sENA-24SEP2026 for SY-sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = ytSena;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemSyToToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)))",
            new address[](6),
            "Burn SY-sENA for sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = sySena;
        leafs[leafIndex].argumentAddresses[2] = sEna;
        leafs[leafIndex].argumentAddresses[3] = sEna;
        leafs[leafIndex].argumentAddresses[4] = address(0);
        leafs[leafIndex].argumentAddresses[5] = address(0);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemDueInterestAndRewards(address,address[],address[],address[])",
            new address[](4),
            "Redeem due interest and rewards for ENA Pendle",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = sySena;
        leafs[leafIndex].argumentAddresses[2] = ytSena;
        leafs[leafIndex].argumentAddresses[3] = ptSenaMarket;
    }
}
