;; Settlement Contract
;; This contract handles compensation for shared inventory

(define-constant ERR-NOT-VERIFIED (err u500))
(define-constant ERR-UNAUTHORIZED (err u501))
(define-constant ERR-AGREEMENT-NOT-FOUND (err u502))
(define-constant ERR-ORDER-NOT-FOUND (err u503))
(define-constant ERR-INVALID-STATUS (err u504))
(define-constant ERR-ALREADY-SETTLED (err u505))
(define-constant ERR-INSUFFICIENT-FUNDS (err u506))

;; Structure for settlements
(define-map settlements
  { order-id: (string-utf8 36) }
  {
    agreement-id: (string-utf8 36),
    owner: principal,
    borrower: principal,
    amount: uint,
    commission: uint,
    status: (string-utf8 20),  ;; "pending", "completed", "disputed"
    settled-at: uint
  }
)

;; Get retailer verification status from retailer-verification contract
(define-read-only (is-verified (retailer principal))
  (contract-call? .retailer-verification is-verified retailer))

;; Get agreement details from sharing-agreement contract
(define-read-only (get-agreement (agreement-id (string-utf8 36)))
  (contract-call? .sharing-agreement get-agreement agreement-id))

;; Get order details from fulfillment-tracking contract
(define-read-only (get-order (order-id (string-utf8 36)))
  (contract-call? .fulfillment-tracking get-order order-id))

;; Create a settlement for a completed order
(define-public (create-settlement (order-id (string-utf8 36)))
  (let (
    (order (get-order order-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    (begin
      ;; Verify retailer
      (asserts! (is-verified tx-sender) ERR-NOT-VERIFIED)

      ;; Check if order exists and is delivered
      (asserts! (is-some order) ERR-ORDER-NOT-FOUND)
      (let (
        (unwrapped-order (unwrap-panic order))
        (agreement-id (get agreement-id (unwrap-panic order)))
        (agreement (get-agreement agreement-id))
      )
        ;; Check if order is delivered
        (asserts! (is-eq (get status unwrapped-order) "delivered") ERR-INVALID-STATUS)

        ;; Check if agreement exists
        (asserts! (is-some agreement) ERR-AGREEMENT-NOT-FOUND)
        (let (
          (unwrapped-agreement (unwrap-panic agreement))
          (owner (get owner unwrapped-agreement))
          (borrower (get borrower unwrapped-agreement))
          (commission-rate (get commission-rate unwrapped-agreement))
        )
          ;; Check if caller is either owner or borrower
          (asserts! (or
            (is-eq tx-sender owner)
            (is-eq tx-sender borrower)
          ) ERR-UNAUTHORIZED)

          ;; Check if settlement already exists
          (asserts! (is-none (map-get? settlements { order-id: order-id })) ERR-ALREADY-SETTLED)

          ;; Calculate settlement amounts
          (let (
            (item-price (unwrap-panic (get-item-price owner (get item-id unwrapped-agreement))))
            (order-quantity (get quantity unwrapped-order))
            (total-amount (* item-price order-quantity))
            (commission-amount (/ (* total-amount commission-rate) u100))
          )
            ;; Create the settlement
            (ok (map-set settlements
              { order-id: order-id }
              {
                agreement-id: agreement-id,
                owner: owner,
                borrower: borrower,
                amount: total-amount,
                commission: commission-amount,
                status: "pending",
                settled-at: current-time
              }
            ))
          )
        )
      )
    )
  )
)

;; Helper function to get item price from inventory
(define-read-only (get-item-price (retailer principal) (item-id (string-utf8 36)))
  (match (contract-call? .inventory-registration get-item retailer item-id)
    item (ok (get price item))
    (err u0)))

;; Complete a settlement (transfer funds)
(define-public (complete-settlement (order-id (string-utf8 36)))
  (match (map-get? settlements { order-id: order-id })
    settlement
      (begin
        ;; Only the borrower can complete settlement
        (asserts! (is-eq tx-sender (get borrower settlement)) ERR-UNAUTHORIZED)

        ;; Check if settlement is pending
        (asserts! (is-eq (get status settlement) "pending") ERR-INVALID-STATUS)

        ;; Transfer funds (in a real implementation, this would involve STX transfers)
        ;; For simplicity, we're just updating the status

        ;; Update settlement status
        (ok (map-set settlements
          { order-id: order-id }
          (merge settlement {
            status: "completed",
            settled-at: (unwrap-panic (get-block-info? time u0))
          })
        ))
      )
    ERR-ORDER-NOT-FOUND
  )
)

;; Dispute a settlement
(define-public (dispute-settlement (order-id (string-utf8 36)))
  (match (map-get? settlements { order-id: order-id })
    settlement
      (begin
        ;; Only owner or borrower can dispute
        (asserts! (or
          (is-eq tx-sender (get owner settlement))
          (is-eq tx-sender (get borrower settlement))
        ) ERR-UNAUTHORIZED)

        ;; Check if settlement is pending
        (asserts! (is-eq (get status settlement) "pending") ERR-INVALID-STATUS)

        ;; Update settlement status
        (ok (map-set settlements
          { order-id: order-id }
          (merge settlement {
            status: "disputed",
            settled-at: (unwrap-panic (get-block-info? time u0))
          })
        ))
      )
    ERR-ORDER-NOT-FOUND
  )
)

;; Get settlement details
(define-read-only (get-settlement (order-id (string-utf8 36)))
  (map-get? settlements { order-id: order-id }))
