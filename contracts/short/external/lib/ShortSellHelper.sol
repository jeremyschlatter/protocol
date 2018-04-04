pragma solidity 0.4.21;
pragma experimental "v0.5.0";

import { ShortSell } from "../../ShortSell.sol";
import { ShortSellCommon } from "../../impl/ShortSellCommon.sol";


library ShortSellHelper {
    function getShort(
        address SHORT_SELL,
        bytes32 shortId
    )
        internal
        view
        returns (ShortSellCommon.Short memory _short)
    {
        address[4] memory addresses;
        uint256[4] memory values256;
        uint32[5] memory values32;

        (
            addresses,
            values256,
            values32
        ) = ShortSell(SHORT_SELL).getShort(shortId);

        return ShortSellCommon.Short({
            underlyingToken: addresses[0],
            baseToken: addresses[1],
            shortAmount: values256[0],
            closedAmount: values256[1],
            interestRate: values256[2],
            requiredDeposit: values256[3],
            callTimeLimit: values32[0],
            startTimestamp: values32[1],
            callTimestamp: values32[2],
            maxDuration: values32[3],
            interestPeriod: values32[4],
            lender: addresses[2],
            seller: addresses[3]
        });
    }
}