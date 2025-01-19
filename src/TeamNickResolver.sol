// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {GatewayFetcher, GatewayRequest} from "@unruggable/gateways/contracts/GatewayFetcher.sol";
import {GatewayFetchTarget, IGatewayVerifier} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/ITextResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";

error Unreachable(bytes dnsname);

event VerifierChanged(address verifier);

address constant TEAMNICK_ADDRESS = 0x7C6EfCb602BC88794390A0d74c75ad2f1249A17f;
uint256 constant SLOT_RECORDS = 7;
uint256 constant SLOT_SUPPLY = 8;

uint256 constant COIN_ETH = 60;
uint256 constant COIN_BASE = 8453 | 0x80000000;

bytes32 constant KEY_AVATAR = keccak256("avatar");
bytes32 constant KEY_URL = keccak256("url");
bytes32 constant KEY_DESCRIPTION = keccak256("description");

bytes4 constant SEL_SUPPLY = 0x00000001;

contract TeamNickResolver is IERC165, Ownable, IExtendedResolver, GatewayFetchTarget {
    using BytesUtils for bytes;
    using GatewayFetcher for GatewayRequest;

    ENS immutable _ens;
    IGatewayVerifier _verifier;
    string _url = "https://teamnick.xyz";

    constructor(ENS ens, IGatewayVerifier verifier) Ownable(msg.sender) {
        _ens = ens;
        _verifier = verifier;
    }

    function supportsInterface(bytes4 x) external pure returns (bool) {
        return x == type(IERC165).interfaceId || x == type(IExtendedResolver).interfaceId;
    }

    function setVerifier(IGatewayVerifier verifier) external onlyOwner {
        _verifier = verifier;
        emit VerifierChanged(address(verifier));
    }

    function setURL(string memory url) external onlyOwner {
        _url = url;
    }

    function resolve(bytes calldata dnsname, bytes calldata data) external view returns (bytes memory) {
        bytes32 labelhash = _parseName(dnsname);
        GatewayRequest memory req = GatewayFetcher.newRequest(1);
        req.setTarget(TEAMNICK_ADDRESS);
        bytes4 selector = bytes4(data);
        if (selector == IAddrResolver.addr.selector) {
            if (labelhash == bytes32(0)) {
                return abi.encode(owner());
            } else {
                req.setSlot(SLOT_RECORDS).push(labelhash).follow().read().setOutput(0);
            }
        } else if (selector == IAddressResolver.addr.selector) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            if (labelhash == bytes32(0)) {
                if (coinType == COIN_ETH) {
                    return abi.encode(abi.encodePacked(owner()));
                } else if (coinType == COIN_BASE) {
                    return abi.encode(abi.encodePacked(TEAMNICK_ADDRESS));
                } else {
                    return abi.encode("");
                }
            } else {
                if (coinType == COIN_ETH) {
                    req.setSlot(SLOT_RECORDS).push(labelhash).follow().read().setOutput(0);
                } else {
                    return abi.encode("");
                }
            }
        } else if (selector == ITextResolver.text.selector) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            bytes32 keyhash = keccak256(bytes(key));
            if (labelhash == bytes32(0)) {
                if (keyhash == KEY_URL) {
                    return abi.encode(_url);
                } else if (keyhash == KEY_DESCRIPTION) {
                    selector = SEL_SUPPLY;
                    req.setSlot(SLOT_SUPPLY).read().setOutput(0);
                } else {
                    return abi.encode("");
                }
            } else {
                if (keyhash == KEY_AVATAR) {
                    req.setSlot(SLOT_RECORDS).push(labelhash).follow().offset(1).readBytes().setOutput(0);
                } else {
                    return abi.encode("");
                }
            }
        } else {
            return new bytes(64);
        }
        fetch(_verifier, req, this.resolveCallback.selector, abi.encode(selector), new string[](0));
    }

    function resolveCallback(bytes[] memory values, uint8, /*exitCode*/ bytes memory data)
        external
        pure
        returns (bytes memory)
    {
        bytes memory value = values[0];
        if (bytes4(data) == SEL_SUPPLY) {
            uint256 supply = uint256(bytes32(values[0]));
            return abi.encode(string.concat(Strings.toString(supply), " names registered"));
        } else if (bytes4(data) == IAddrResolver.addr.selector) {
            return value; //abi.encode(bytes32(value));
        } else if (bytes4(data) == IAddressResolver.addr.selector) {
            return abi.encode(abi.encodePacked(uint160(uint256(bytes32(value)))));
        } else {
            return abi.encode(value);
        }
    }

    function _parseName(bytes memory dnsname) internal view returns (bytes32) {
        uint256 prev;
        uint256 offset;
        while (true) {
            bytes32 node = dnsname.namehash(offset);
            if (_ens.resolver(node) == address(this)) break;
            uint256 size = uint8(dnsname[offset]);
            if (size == 0) revert Unreachable(dnsname);
            prev = 1 + offset;
            offset = prev + size;
        }
        return offset == 0 ? bytes32(0) : dnsname.keccak(prev, offset - prev);
    }
}
