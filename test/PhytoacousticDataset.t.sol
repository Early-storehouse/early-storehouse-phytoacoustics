// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PhytoacousticDataset} from "../src/PhytoacousticDataset.sol";

contract PhytoacousticDatasetTest is Test {
    PhytoacousticDataset internal dataset;

    address internal owner;
    address internal researcher;
    address internal recipient;

    string internal constant ARWEAVE_URI = "ar://bundle-txid/metadata.json";
    string internal constant CONTENT_HASH = "sha256:0abc123def456";
    string internal constant CROP = "radish";
    string internal constant TREATMENT = "acoustic";
    uint32 internal constant FREQ = 250;

    event DatasetPublished(
        uint256 indexed tokenId,
        address indexed researcher,
        string contentHash,
        string crop,
        string treatment,
        uint32 frequencyHz,
        uint64 timestamp
    );
    event DatasetSoulboundSet(uint256 indexed tokenId, bool locked);
    event DatasetURIUpdated(uint256 indexed tokenId, string uri);

    function setUp() public {
        owner = makeAddr("owner");
        researcher = makeAddr("researcher");
        recipient = makeAddr("recipient");

        vm.warp(1_700_000_000);
        vm.prank(owner);
        dataset = new PhytoacousticDataset(owner);
    }

    /// @dev Publish one default dataset as the owner and return its id.
    function _publish() internal returns (uint256) {
        vm.prank(owner);
        return dataset.publish(researcher, ARWEAVE_URI, CONTENT_HASH, CROP, FREQ, TREATMENT);
    }

    // -------------------------------------------------------------------
    // publish
    // -------------------------------------------------------------------

    function test_publish_mintsSingleTokenToResearcher() public {
        uint256 tokenId = _publish();

        assertEq(tokenId, 1);
        assertEq(dataset.balanceOf(researcher, tokenId), 1);
        assertEq(dataset.datasetCount(), 1);
    }

    function test_publish_storesProvenanceRecord() public {
        uint256 tokenId = _publish();
        PhytoacousticDataset.DatasetRecord memory rec = dataset.record(tokenId);

        assertEq(rec.contentHash, CONTENT_HASH);
        assertEq(rec.crop, CROP);
        assertEq(rec.treatment, TREATMENT);
        assertEq(rec.frequencyHz, FREQ);
        assertEq(rec.timestamp, uint64(block.timestamp));
    }

    function test_publish_setsTokenURI() public {
        uint256 tokenId = _publish();
        assertEq(dataset.uri(tokenId), ARWEAVE_URI);
    }

    function test_publish_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit DatasetPublished(1, researcher, CONTENT_HASH, CROP, TREATMENT, FREQ, uint64(block.timestamp));
        _publish();
    }

    function test_publish_incrementsIdsForSuccessiveDatasets() public {
        uint256 first = _publish();

        vm.prank(owner);
        uint256 second = dataset.publish(researcher, ARWEAVE_URI, "sha256:second", "carrot", 0, "control");

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(dataset.datasetCount(), 2);
    }

    function test_publish_revertsForNonOwner() public {
        vm.prank(researcher);
        vm.expectRevert();
        dataset.publish(researcher, ARWEAVE_URI, CONTENT_HASH, CROP, FREQ, TREATMENT);
    }

    function test_publish_revertsForZeroResearcher() public {
        vm.prank(owner);
        vm.expectRevert(PhytoacousticDataset.InvalidResearcher.selector);
        dataset.publish(address(0), ARWEAVE_URI, CONTENT_HASH, CROP, FREQ, TREATMENT);
    }

    function test_publish_revertsForEmptyContentHash() public {
        vm.prank(owner);
        vm.expectRevert(PhytoacousticDataset.EmptyContentHash.selector);
        dataset.publish(researcher, ARWEAVE_URI, "", CROP, FREQ, TREATMENT);
    }

    // -------------------------------------------------------------------
    // transferability & soulbound toggle
    // -------------------------------------------------------------------

    function test_tokensAreTransferableByDefault() public {
        uint256 tokenId = _publish();

        vm.prank(researcher);
        dataset.safeTransferFrom(researcher, recipient, tokenId, 1, "");

        assertEq(dataset.balanceOf(recipient, tokenId), 1);
        assertEq(dataset.balanceOf(researcher, tokenId), 0);
    }

    function test_setSoulbound_blocksTransfer() public {
        uint256 tokenId = _publish();

        vm.prank(owner);
        dataset.setSoulbound(tokenId, true);

        vm.prank(researcher);
        vm.expectRevert(abi.encodeWithSelector(PhytoacousticDataset.DatasetIsSoulbound.selector, tokenId));
        dataset.safeTransferFrom(researcher, recipient, tokenId, 1, "");
    }

    function test_setSoulbound_emitsEvent() public {
        uint256 tokenId = _publish();

        vm.expectEmit(true, false, false, true);
        emit DatasetSoulboundSet(tokenId, true);

        vm.prank(owner);
        dataset.setSoulbound(tokenId, true);
    }

    function test_setSoulbound_isReversible() public {
        uint256 tokenId = _publish();

        vm.startPrank(owner);
        dataset.setSoulbound(tokenId, true);
        dataset.setSoulbound(tokenId, false);
        vm.stopPrank();

        vm.prank(researcher);
        dataset.safeTransferFrom(researcher, recipient, tokenId, 1, "");
        assertEq(dataset.balanceOf(recipient, tokenId), 1);
    }

    function test_setSoulbound_stillAllowsBurn() public {
        uint256 tokenId = _publish();

        vm.prank(owner);
        dataset.setSoulbound(tokenId, true);

        vm.prank(researcher); // the token holder burns their own dataset
        dataset.burn(researcher, tokenId, 1);

        assertEq(dataset.balanceOf(researcher, tokenId), 0);
    }

    function test_setSoulbound_onlyOwner() public {
        uint256 tokenId = _publish();

        vm.prank(researcher);
        vm.expectRevert();
        dataset.setSoulbound(tokenId, true);
    }

    function test_setSoulbound_revertsForUnknownDataset() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PhytoacousticDataset.UnknownDataset.selector, 42));
        dataset.setSoulbound(42, true);
    }

    // -------------------------------------------------------------------
    // metadata URI
    // -------------------------------------------------------------------

    function test_setDatasetURI_updatesUri() public {
        uint256 tokenId = _publish();

        vm.expectEmit(true, false, false, true);
        emit DatasetURIUpdated(tokenId, "ar://new-bundle/metadata.json");

        vm.prank(owner);
        dataset.setDatasetURI(tokenId, "ar://new-bundle/metadata.json");

        assertEq(dataset.uri(tokenId), "ar://new-bundle/metadata.json");
    }

    function test_setDatasetURI_onlyOwner() public {
        uint256 tokenId = _publish();

        vm.prank(researcher);
        vm.expectRevert();
        dataset.setDatasetURI(tokenId, "ar://nope");
    }

    // -------------------------------------------------------------------
    // records & introspection
    // -------------------------------------------------------------------

    function test_record_revertsForUnknownDataset() public {
        vm.expectRevert(abi.encodeWithSelector(PhytoacousticDataset.UnknownDataset.selector, 99));
        dataset.record(99);
    }

    function test_metadata_nameAndSymbol() public view {
        assertEq(dataset.name(), "Early Storehouse Phytoacoustic Datasets");
        assertEq(dataset.symbol(), "ESPAD");
    }

    function test_supportsInterface() public view {
        assertTrue(dataset.supportsInterface(0xd9b67a26)); // ERC-1155
        assertTrue(dataset.supportsInterface(0x0e89341c)); // ERC-1155MetadataURI
    }

    function test_ownerIsSet() public view {
        assertEq(dataset.owner(), owner);
    }
}
