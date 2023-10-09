// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {ERC1155} from "solady/tokens/ERC1155.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFriendtech {
    function getBuyPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function getSellPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function buyShares(address sharesSubject, uint256 amount) external payable;

    function sellShares(address sharesSubject, uint256 amount) external;
}

contract WrappedFriendtech is Ownable, ERC1155 {
    using LibString for uint256;
    using SafeTransferLib for address;

    IFriendtech public constant FRIENDTECH =
        IFriendtech(0xCF205808Ed36593aa40a44F10c7f7C2F67d4A4d4);

    // Can be changed via the setter below (necessary should maintainership change).
    string public baseURI = "https://prod-api.kosetto.com/users/";

    error ZeroAmount();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    // Overridden to enforce 2-step ownership transfers.
    function transferOwnership(address) public payable override {}

    // Overridden to enforce 2-step ownership transfers.
    function renounceOwnership() public payable override {}

    /**
     * @notice Set a new value for `baseURI`.
     * @param  newBaseURI  string  New base URI.
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;

        // We're maintaining one baseURI for all token IDs.
        emit URI(newBaseURI, type(uint256).max);
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given token.
     * @param  id   uint256  Token ID.
     * @return URI  string   A JSON file that conforms to the "ERC-1155 Metadata URI JSON Schema".
     */
    function uri(uint256 id) public view override returns (string memory) {
        return string.concat(baseURI, id.toString());
    }

    /**
     * @notice Mints wrapped FT shares.
     * @dev    Follows the checks-effects-interactions pattern to prevent reentrancy.
     * @dev    Emits the `TransferSingle` event as a result of calling `_mint`.
     * @param  sharesSubject  address  Friendtech user address.
     * @param  amount         uint256  Shares amount.
     */
    function wrap(address sharesSubject, uint256 amount) external payable {
        if (amount == 0) revert ZeroAmount();

        // The token ID is the uint256-casted `sharesSubject` address.
        _mint(msg.sender, uint256(uint160(sharesSubject)), amount, "");

        uint256 price = FRIENDTECH.getBuyPriceAfterFee(sharesSubject, amount);

        // Throws if `sharesSubject` is the zero address ("Only the shares' subject can buy the first share").
        // Throws if `msg.value` is insufficient since this contract will not (intentionally) maintain an ETH balance.
        FRIENDTECH.buyShares{value: price}(sharesSubject, amount);

        if (msg.value > price) {
            // Will not underflow since `msg.value` is greater than `price`.
            unchecked {
                msg.sender.safeTransferETH(msg.value - price);
            }
        }
    }

    /**
     * @notice Burns wrapped FT shares.
     * @dev    Follows the checks-effects-interactions pattern to prevent reentrancy.
     * @dev    Emits the `TransferSingle` event as a result of calling `_burn`.
     * @param  sharesSubject  address  Friendtech user address.
     * @param  amount         uint256  Shares amount.
     */
    function unwrap(address sharesSubject, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, uint256(uint160(sharesSubject)), amount);

        // Throws if `sharesSubject` is the zero address.
        FRIENDTECH.sellShares(sharesSubject, amount);

        // Transfer the contract's ETH balance since it should only have ETH from the share sale.
        msg.sender.safeTransferETH(address(this).balance);
    }
}