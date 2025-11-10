## Buy Now: Fixed Price

```mermaid
sequenceDiagram
    autonumber
    actor Buyer as Buyer (User/App)
    participant ARIO as ARIO Token Process
    participant ANT as ANT Token Process
    participant Market as Marketplace Process
    participant Treasury as Treasury (fees)

    Buyer->>ARIO: sendMessage(... X-Order-Action=Create-Order, Quantity=sentARIO)
    ARIO->>Market: Transfer with forwarded X-* tags

    Market->>Market: fixed_price.handleAntOrder(args)
    Market->>Market: Validate order exists, not expired, requestedOrderId matches
    Market->>Market: requiredAmount = listed Price
    alt sentARIO >= requiredAmount
        Market->>Treasury: sendFeeToTreasury(requiredAmount, ...)
        Market->>ARIO: Transfer ARIO to Seller (minus fee)
        opt Overpayment
            Market->>ARIO: Refund excess ARIO to Buyer
        end
        Market->>ANT: Transfer ANT to Buyer
        Market->>Market: recordExecutedOrder(...)
        Market-->>Buyer: Order-Success (fixed)
    else Insufficient
        Market-->>Buyer: Order-Error (Insufficient payment)
    end
```


