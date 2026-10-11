// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  PhytoacousticDataset
 * @author Early Storehouse
 * @notice On-chain provenance registry for phytoacoustic trial data.
 *
 * @dev Each published trial dataset is minted as a unique ERC-1155 token
 *      (id >= 1, supply == 1) whose immutable provenance record - an
 *      Arweave/IPFS content hash plus the experimental parameters - is
 *      written on-chain at the moment of publication. This gives a
 *      tamper-evident timestamp for null results as well as positive ones,
 *      which is the credibility primitive the DeSci funding programmes
 *      (ValleyDAO, Gitcoin, Bio.xyz) expect to see.
 *
 *      Tokens are transferable by default, keeping them interoperable with
 *      wallets, marketplaces and DeSci tooling and leaving the door open to
 *      IP-NFT style mechanics later. The owner (intended to be a Gnosis Safe
 *      multisig on Optimism) may additionally flag an individual dataset as
 *      "soulbound" to freeze it as a permanent historical record. The
 *      provenance itself lives in a mapping and is therefore unaffected by
 *      whether a given token can be transferred.
 */
contract PhytoacousticDataset is ERC1155URIStorage, ERC1155Burnable, Ownable {
    /// @notice Immutable provenance record attached to a published dataset.
    struct DatasetRecord {
        string contentHash; // sha256 / CID of the dataset (e.g. "bafy...", "ar://...")
        string crop; // crop under trial, e.g. "radish"
        string treatment; // treatment label, e.g. "acoustic" or "control"
        uint32 frequencyHz; // acoustic frequency applied, in Hz (0 for controls)
        uint64 timestamp; // block timestamp at the moment of publication
    }

    /// @notice Number of datasets published so far (also the highest token id).
    uint256 public datasetCount;

    /// @dev tokenId => provenance record.
    mapping(uint256 tokenId => DatasetRecord) private _records;

    /// @notice tokenId => whether transfers are frozen (soulbound).
    mapping(uint256 tokenId => bool) public soulbound;

    /// @notice Emitted when a new dataset is published and its token minted.
    event DatasetPublished(
        uint256 indexed tokenId,
        address indexed researcher,
        string contentHash,
        string crop,
        string treatment,
        uint32 frequencyHz,
        uint64 timestamp
    );

    /// @notice Emitted when a dataset is locked into (or released from) soulbound mode.
    event DatasetSoulboundSet(uint256 indexed tokenId, bool locked);

    /// @notice Emitted when the metadata URI of an existing dataset is updated.
    event DatasetURIUpdated(uint256 indexed tokenId, string uri);

    error EmptyContentHash();
    error InvalidResearcher();
    error UnknownDataset(uint256 tokenId);
    error DatasetIsSoulbound(uint256 tokenId);

    /**
     * @param initialOwner Address able to publish datasets and manage the
     *        registry. On Optimism this should be the Gnosis Safe multisig.
     */
    constructor(address initialOwner) ERC1155("") Ownable(initialOwner) {}

    /// @notice Human-readable collection name (read by some marketplaces).
    function name() external pure returns (string memory) {
        return "Early Storehouse Phytoacoustic Datasets";
    }

    /// @notice Collection symbol (read by some marketplaces).
    function symbol() external pure returns (string memory) {
        return "ESPAD";
    }

    /**
     * @dev Resolves the {ERC1155} / {ERC1155URIStorage} `uri` ambiguity caused by
     *      inheriting both extensions, delegating to the storage-backed lookup.
     */
    function uri(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155, ERC1155URIStorage)
        returns (string memory)
    {
        return super.uri(tokenId);
    }

    /**
     * @notice Publish a new trial dataset and mint its certificate of provenance.
     * @dev    Owner-only. Mints exactly one token of a fresh id to `researcher`.
     * @param researcher  Recipient of the dataset token (the research wallet).
     * @param uri_        Metadata URI, typically an `ar://` (Arweave) pointer.
     * @param contentHash Content hash / CID of the underlying dataset.
     * @param crop        Crop under trial.
     * @param frequencyHz Acoustic frequency applied, in Hz (0 for a control group).
     * @param treatment   Treatment label, e.g. "acoustic" or "control".
     * @return tokenId    The newly minted dataset id.
     */
    function publish(
        address researcher,
        string calldata uri_,
        string calldata contentHash,
        string calldata crop,
        uint32 frequencyHz,
        string calldata treatment
    ) external onlyOwner returns (uint256 tokenId) {
        if (researcher == address(0)) revert InvalidResearcher();
        if (bytes(contentHash).length == 0) revert EmptyContentHash();

        unchecked {
            tokenId = ++datasetCount; // cannot realistically overflow uint256
        }

        uint64 publishedAt = uint64(block.timestamp);

        _records[tokenId] = DatasetRecord({
            contentHash: contentHash,
            crop: crop,
            treatment: treatment,
            frequencyHz: frequencyHz,
            timestamp: publishedAt
        });

        _mint(researcher, tokenId, 1, "");
        _setURI(tokenId, uri_);

        emit DatasetPublished(tokenId, researcher, contentHash, crop, treatment, frequencyHz, publishedAt);
    }

    /**
     * @notice Update the metadata URI of an already published dataset.
     * @dev    Owner-only. Useful when an Arweave bundle is re-pinned. The
     *         content hash of the dataset itself is never mutable.
     */
    function setDatasetURI(uint256 tokenId, string calldata uri_) external onlyOwner {
        _requireKnown(tokenId);
        _setURI(tokenId, uri_);
        emit DatasetURIUpdated(tokenId, uri_);
    }

    /**
     * @notice Freeze (or unfreeze) an individual dataset as a permanent record.
     * @dev    Owner-only. While locked the token cannot be transferred, but it
     *         can still be burned. This is the hybrid soulbound toggle.
     */
    function setSoulbound(uint256 tokenId, bool locked) external onlyOwner {
        _requireKnown(tokenId);
        soulbound[tokenId] = locked;
        emit DatasetSoulboundSet(tokenId, locked);
    }

    /// @notice Return the full provenance record for a dataset id.
    function record(uint256 tokenId) external view returns (DatasetRecord memory) {
        _requireKnown(tokenId);
        return _records[tokenId];
    }

    /**
     * @dev ERC-1155 transfer hook. Blocks transfers of soulbound datasets while
     *      still permitting minting (from == 0) and burning (to == 0).
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        if (from != address(0) && to != address(0)) {
            uint256 length = ids.length;
            for (uint256 i; i < length; ++i) {
                if (soulbound[ids[i]]) revert DatasetIsSoulbound(ids[i]);
            }
        }
        super._update(from, to, ids, values);
    }

    /// @dev Reverts with {UnknownDataset} when `tokenId` has never been published.
    function _requireKnown(uint256 tokenId) private view {
        if (tokenId == 0 || tokenId > datasetCount) revert UnknownDataset(tokenId);
    }
}
