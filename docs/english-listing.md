## Listing: English Auction (ARIO-dominant)

```mermaid
sequenceDiagram
    autonumber
    actor User as User/App
    participant ARIO as ARIO Token Process
    participant ANT as ANT Token Process
    participant Market as Marketplace Process

    User->>ANT: sendMessage(... X-Order-Action=Create-Order, X-Order-Type=english, X-Expiration-Time, X-Price, Quantity=ANT)
    ANT->>Market: Transfer with forwarded X-* tags

    Market->>Market: english_auction.handleArioOrder(args)
    Market->>Market: recordListedOrder(..., ExpirationTime)
    Market-->>User: Order-Success (OrderType=english, Price, Quantity, X-Group-ID)
```


