;; IP License Expiration and Renewal Smart Contract
;; Manages time-limited IP licenses with automatic renewal capabilities

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_LICENSE_NOT_FOUND (err u101))
(define-constant ERR_LICENSE_EXPIRED (err u102))
(define-constant ERR_INVALID_EXPIRATION (err u103))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u104))
(define-constant ERR_RENEWAL_FAILED (err u105))
(define-constant ERR_INVALID_TOKEN_ID (err u106))

;; Data Variables
(define-data-var next-license-id uint u1)
(define-data-var contract-owner principal CONTRACT_OWNER)
(define-data-var default-license-duration uint u31536000) ;; 1 year in seconds
(define-data-var renewal-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map licenses
  { token-id: uint }
  {
    owner: principal,
    ip-hash: (string-ascii 64),
    expiration-date: uint,
    auto-renew: bool,
    renewal-fee: uint,
    created-at: uint
  }
)

(define-map authorized-operators
  { operator: principal }
  { authorized: bool }
)

(define-map license-renewals
  { token-id: uint, renewal-count: uint }
  {
    renewed-at: uint,
    renewed-by: principal,
    fee-paid: uint
  }
)

;; Add this new map after the existing maps
(define-map license-renewal-counts
  { token-id: uint }
  { count: uint }
)

;; Read-only functions

(define-read-only (get-license (token-id uint))
  (map-get? licenses { token-id: token-id })
)

(define-read-only (is-license-valid (token-id uint))
  (match (get-license token-id)
    license (> (get expiration-date license) stacks-block-height)
    false
  )
)

(define-read-only (get-expiration-date (token-id uint))
  (match (get-license token-id)
    license (ok (get expiration-date license))
    ERR_LICENSE_NOT_FOUND
  )
)

(define-read-only (get-time-until-expiration (token-id uint))
  (match (get-license token-id)
    license 
      (let ((expiration (get expiration-date license)))
        (if (> expiration stacks-block-height)
          (ok (- expiration stacks-block-height))
          (ok u0)
        )
      )
    ERR_LICENSE_NOT_FOUND
  )
)

(define-read-only (is-authorized-operator (operator principal))
  (default-to false (get authorized (map-get? authorized-operators { operator: operator })))
)

(define-read-only (get-renewal-fee)
  (var-get renewal-fee)
)

(define-read-only (get-license-owner (token-id uint))
  (match (get-license token-id)
    license (ok (get owner license))
    ERR_LICENSE_NOT_FOUND
  )
)

;; Authorization functions

(define-private (is-owner-or-operator (caller principal))
  (or 
    (is-eq caller (var-get contract-owner))
    (is-authorized-operator caller)
  )
)

(define-private (is-license-owner (token-id uint) (caller principal))
  (match (get-license token-id)
    license (is-eq caller (get owner license))
    false
  )
)

;; Public functions

(define-public (create-license (owner principal) (ip-hash (string-ascii 64)) (duration uint))
  (let 
    (
      (token-id (var-get next-license-id))
      (expiration-date (+ stacks-block-height duration))
    )
    (asserts! (is-owner-or-operator tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> duration u0) ERR_INVALID_EXPIRATION)
    
    (map-set licenses
      { token-id: token-id }
      {
        owner: owner,
        ip-hash: ip-hash,
        expiration-date: expiration-date,
        auto-renew: false,
        renewal-fee: (var-get renewal-fee),
        created-at: stacks-block-height
      }
    )
    
    (var-set next-license-id (+ token-id u1))
    (print { event: "license-created", token-id: token-id, owner: owner, expiration: expiration-date })
    (ok token-id)
  )
)

(define-public (set-expiration-date (token-id uint) (expiration-timestamp uint))
  (let ((license (unwrap! (get-license token-id) ERR_LICENSE_NOT_FOUND)))
    (asserts! 
      (or 
        (is-owner-or-operator tx-sender)
        (is-license-owner token-id tx-sender)
      ) 
      ERR_NOT_AUTHORIZED
    )
    (asserts! (> expiration-timestamp stacks-block-height) ERR_INVALID_EXPIRATION)
    
    (map-set licenses
      { token-id: token-id }
      (merge license { expiration-date: expiration-timestamp })
    )
    
    (print { event: "expiration-updated", token-id: token-id, new-expiration: expiration-timestamp })
    (ok true)
  )
)

(define-public (renew-license (token-id uint))
  (let 
    (
      (license (unwrap! (get-license token-id) ERR_LICENSE_NOT_FOUND))
      (renewal-fee-amount (get renewal-fee license))
      (new-expiration (+ (get expiration-date license) (var-get default-license-duration)))
      (current-count (default-to u0 (get count (map-get? license-renewal-counts { token-id: token-id }))))
      (new-count (+ current-count u1))
    )
    (asserts! 
      (or 
        (is-license-owner token-id tx-sender)
        (is-owner-or-operator tx-sender)
      ) 
      ERR_NOT_AUTHORIZED
    )
    
    ;; Process payment
    (try! (stx-transfer? renewal-fee-amount tx-sender (var-get contract-owner)))
    
    ;; Update license expiration
    (map-set licenses
      { token-id: token-id }
      (merge license { expiration-date: new-expiration })
    )
    
    ;; Update renewal count
    (map-set license-renewal-counts
      { token-id: token-id }
      { count: new-count }
    )
    
    ;; Record renewal details
    (map-set license-renewals
      { token-id: token-id, renewal-count: new-count }
      {
        renewed-at: stacks-block-height,
        renewed-by: tx-sender,
        fee-paid: renewal-fee-amount
      }
    )
    
    (print { event: "license-renewed", token-id: token-id, new-expiration: new-expiration, fee-paid: renewal-fee-amount, renewal-count: new-count })
    (ok new-expiration)
  )
)

(define-public (set-auto-renewal (token-id uint) (auto-renew bool))
  (let ((license (unwrap! (get-license token-id) ERR_LICENSE_NOT_FOUND)))
    (asserts! (is-license-owner token-id tx-sender) ERR_NOT_AUTHORIZED)
    
    (map-set licenses
      { token-id: token-id }
      (merge license { auto-renew: auto-renew })
    )
    
    (print { event: "auto-renewal-updated", token-id: token-id, auto-renew: auto-renew })
    (ok true)
  )
)

(define-public (process-auto-renewal (token-id uint))
  (let 
    (
      (license (unwrap! (get-license token-id) ERR_LICENSE_NOT_FOUND))
      (expiration (get expiration-date license))
      (auto-renew (get auto-renew license))
      (owner (get owner license))
    )
    (asserts! auto-renew ERR_NOT_AUTHORIZED)
    (asserts! (<= (- expiration stacks-block-height) u1440) ERR_INVALID_EXPIRATION) ;; Within 1440 blocks (~1 day)
    
    ;; Auto-renewal logic - in a real implementation, this would need external payment handling
    (let ((new-expiration (+ expiration (var-get default-license-duration))))
      (map-set licenses
        { token-id: token-id }
        (merge license { expiration-date: new-expiration })
      )
      
      (print { event: "auto-renewal-processed", token-id: token-id, new-expiration: new-expiration })
      (ok new-expiration)
    )
  )
)

;; Admin functions

(define-public (add-authorized-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set authorized-operators { operator: operator } { authorized: true })
    (print { event: "operator-authorized", operator: operator })
    (ok true)
  )
)

(define-public (remove-authorized-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set authorized-operators { operator: operator } { authorized: false })
    (print { event: "operator-removed", operator: operator })
    (ok true)
  )
)

(define-public (set-renewal-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (var-set renewal-fee new-fee)
    (print { event: "renewal-fee-updated", new-fee: new-fee })
    (ok true)
  )
)

(define-public (set-default-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> new-duration u0) ERR_INVALID_EXPIRATION)
    (var-set default-license-duration new-duration)
    (print { event: "default-duration-updated", new-duration: new-duration })
    (ok true)
  )
)

;; Batch operations

(define-public (check-multiple-licenses (token-ids (list 10 uint)))
  (ok (map is-license-valid token-ids))
)

(define-public (get-multiple-expirations (token-ids (list 10 uint)))
  (ok (map get-expiration-date token-ids))
)

;; Emergency functions

(define-public (emergency-extend-license (token-id uint) (additional-time uint))
  (let ((license (unwrap! (get-license token-id) ERR_LICENSE_NOT_FOUND)))
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    
    (let ((new-expiration (+ (get expiration-date license) additional-time)))
      (map-set licenses
        { token-id: token-id }
        (merge license { expiration-date: new-expiration })
      )
      
      (print { event: "emergency-extension", token-id: token-id, additional-time: additional-time })
      (ok new-expiration)
    )
  )
)

(define-read-only (get-renewal-count (token-id uint))
  (default-to u0 (get count (map-get? license-renewal-counts { token-id: token-id })))
)
