
;; title: royalty-distribution
;; version:
;; summary:
;; description:

;; Royalty Distribution Contract
;; Handles automatic distribution of royalties to creators and stakeholders

;; Constants for errors and configuration
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-RECIPIENT (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-DISTRIBUTION-FAILED (err u104))
(define-constant ERR-INVALID-SHARES (err u105))

;; Data Variables
(define-map creator-shares
    principal  ;; creator address
    {
        share-percentage: uint,  ;; stored as basis points (1/100th of a percent)
        total-received: uint,    ;; total amount received
        last-payout: uint       ;; block height of last payout
    }
)

(define-map pending-royalties
    principal  ;; creator address
    uint      ;; amount pending
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Total shares issued (must equal 10000 basis points = 100%)
(define-data-var total-shares uint u0)

;; Read-only functions
(define-read-only (get-creator-share (creator principal))
    (map-get? creator-shares creator)
)

(define-read-only (get-pending-royalties (creator principal))
    (default-to u0 (map-get? pending-royalties creator))
)

;; Public functions
(define-public (set-creator-share (creator principal) (share-bps uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR-UNAUTHORIZED)
        (asserts! (<= share-bps u10000) ERR-INVALID-SHARES)
        
        ;; Calculate new total shares
        (let (
            (current-share (default-to u0 (get share-percentage (get-creator-share creator))))
            (new-total (+ (- (var-get total-shares) current-share) share-bps))
        )
            ;; Ensure total shares don't exceed 100%
            (asserts! (<= new-total u10000) ERR-INVALID-SHARES)
            
            ;; Update creator share
            (map-set creator-shares creator {
                share-percentage: share-bps,
                total-received: (default-to u0 (get total-received (get-creator-share creator))),
                last-payout: block-height
            })
            
            ;; Update total shares
            (var-set total-shares new-total)
            (ok true)
        )
    )
)

(define-public (distribute-royalties (total-amount uint))
    (begin
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        ;; Check if contract has sufficient balance
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) total-amount) ERR-INSUFFICIENT-FUNDS)
        
        ;; Distribute to each creator based on their share
        (try! (distribute-to-creators total-amount))
        (ok true)
    )
)

(define-public (withdraw-royalties)
    (let (
        (pending-amount (get-pending-royalties tx-sender))
    )
        (begin
            (asserts! (> pending-amount u0) ERR-INSUFFICIENT-FUNDS)
            (try! (as-contract (stx-transfer? pending-amount tx-sender tx-sender)))
            (map-delete pending-royalties tx-sender)
            (ok pending-amount)
        )
    )
)

;; Private functions
(define-private (distribute-to-creators (total-amount uint))
    (begin
        (asserts! (> (var-get total-shares) u0) ERR-INVALID-SHARES)
        (map-set pending-royalties 
            tx-sender
            (+ (get-pending-royalties tx-sender)
               (/ (* total-amount (unwrap-panic (get share-percentage (get-creator-share tx-sender)))) u10000)))
        (ok true)
    )
)

(define-private (is-contract-owner (caller principal))
    (is-eq caller (var-get contract-owner))
)