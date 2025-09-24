;; IP Geolocation & Usage Restrictions Smart Contract
;; Allows IP owners to define geographic restrictions for their intellectual property

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-NOT-FOUND (err u101))
(define-constant ERR-INVALID-REGION (err u102))
(define-constant ERR-REGION-RESTRICTED (err u103))
(define-constant ERR-INVALID-TOKEN-ID (err u104))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map token-owners uint principal)
(define-map token-metadata uint {
    title: (string-ascii 256),
    creator: principal,
    created-at: uint
})

;; Geolocation restrictions map
;; Maps token ID to a list of restricted regions
(define-map geolocation-restrictions uint (list 50 (string-ascii 10)))

;; Allowed regions map (alternative approach - whitelist instead of blacklist)
(define-map allowed-regions uint (list 50 (string-ascii 10)))

;; Usage tracking
(define-map usage-attempts {token-id: uint, user: principal, region: (string-ascii 10)} {
    timestamp: uint,
    allowed: bool
})

;; Token counter
(define-data-var token-id-nonce uint u0)

;; Mint new IP token
(define-public (mint-ip-token (title (string-ascii 256)) (recipient principal))
    (let ((token-id (+ (var-get token-id-nonce) u1)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set token-owners token-id recipient)
        (map-set token-metadata token-id {
            title: title,
            creator: recipient,
            created-at: block-height
        })
        (var-set token-id-nonce token-id)
        (ok token-id)
    )
)

;; Set geolocation restrictions (blacklist approach)
(define-public (set-geolocation-restrictions (token-id uint) (restricted-regions (list 50 (string-ascii 10))))
    (let ((token-owner (unwrap! (map-get? token-owners token-id) ERR-TOKEN-NOT-FOUND)))
        (asserts! (is-eq tx-sender token-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> token-id u0) ERR-INVALID-TOKEN-ID)
        (map-set geolocation-restrictions token-id restricted-regions)
        (ok true)
    )
)

;; Set allowed regions (whitelist approach)
(define-public (set-allowed-regions (token-id uint) (regions (list 50 (string-ascii 10))))
    (let ((token-owner (unwrap! (map-get? token-owners token-id) ERR-TOKEN-NOT-FOUND)))
        (asserts! (is-eq tx-sender token-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> token-id u0) ERR-INVALID-TOKEN-ID)
        (map-set allowed-regions token-id regions)
        (ok true)
    )
)

;; Check if usage is allowed in a specific region
(define-public (check-usage-permission (token-id uint) (user-region (string-ascii 10)))
    (let (
        (restricted-regions (default-to (list) (map-get? geolocation-restrictions token-id)))
        (allowed-regions-list (default-to (list) (map-get? allowed-regions token-id)))
        (is-restricted (is-some (index-of restricted-regions user-region)))
        (is-in-allowed-list (is-some (index-of allowed-regions-list user-region)))
        (has-allowed-list (> (len allowed-regions-list) u0))
    )
        ;; Fixed syntax error by using is-some to check if token exists
        (asserts! (is-some (map-get? token-owners token-id)) ERR-TOKEN-NOT-FOUND)
        
        ;; Log usage attempt
        (map-set usage-attempts 
            {token-id: token-id, user: tx-sender, region: user-region}
            {timestamp: block-height, allowed: (and (not is-restricted) (or (not has-allowed-list) is-in-allowed-list))}
        )
        
        ;; Check restrictions
        (asserts! (not is-restricted) ERR-REGION-RESTRICTED)
        
        ;; If there's an allowed list, user must be in it
        (if has-allowed-list
            (asserts! is-in-allowed-list ERR-REGION-RESTRICTED)
            true
        )
        
        (ok true)
    )
)

;; Use IP content (with region verification)
(define-public (use-ip-content (token-id uint) (user-region (string-ascii 10)))
    (begin
        (try! (check-usage-permission token-id user-region))
        ;; Additional usage logic can be added here
        (ok {
            token-id: token-id,
            user: tx-sender,
            region: user-region,
            timestamp: block-height
        })
    )
)

;; Transfer token ownership
(define-public (transfer-token (token-id uint) (new-owner principal))
    (let ((current-owner (unwrap! (map-get? token-owners token-id) ERR-TOKEN-NOT-FOUND)))
        (asserts! (is-eq tx-sender current-owner) ERR-NOT-AUTHORIZED)
        (map-set token-owners token-id new-owner)
        (ok true)
    )
)

;; Add region to restrictions
(define-public (add-restricted-region (token-id uint) (region (string-ascii 10)))
    (let (
        (token-owner (unwrap! (map-get? token-owners token-id) ERR-TOKEN-NOT-FOUND))
        (current-restrictions (default-to (list) (map-get? geolocation-restrictions token-id)))
    )
        (asserts! (is-eq tx-sender token-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (index-of current-restrictions region)) ERR-INVALID-REGION)
        (map-set geolocation-restrictions token-id (unwrap! (as-max-len? (append current-restrictions region) u50) ERR-INVALID-REGION))
        (ok true)
    )
)

;; Remove region from restrictions
(define-public (remove-restricted-region (token-id uint) (region (string-ascii 10)))
    (let (
        (token-owner (unwrap! (map-get? token-owners token-id) ERR-TOKEN-NOT-FOUND))
        (current-restrictions (default-to (list) (map-get? geolocation-restrictions token-id)))
        (filtered-restrictions (filter is-not-target-region current-restrictions))
    )
        (asserts! (is-eq tx-sender token-owner) ERR-NOT-AUTHORIZED)
        (map-set geolocation-restrictions token-id filtered-restrictions)
        (ok true)
    )
)

;; Helper function for filtering regions
(define-private (is-not-target-region (region (string-ascii 10)))
    ;; This would need to be implemented with the specific region to remove
    ;; For now, this is a placeholder
    true
)

;; Read-only functions

;; Get token owner
(define-read-only (get-token-owner (token-id uint))
    (map-get? token-owners token-id)
)

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
    (map-get? token-metadata token-id)
)

;; Get restricted regions for a token
(define-read-only (get-restricted-regions (token-id uint))
    (default-to (list) (map-get? geolocation-restrictions token-id))
)

;; Get allowed regions for a token
(define-read-only (get-allowed-regions (token-id uint))
    (default-to (list) (map-get? allowed-regions token-id))
)

;; Check if region is restricted
(define-read-only (is-region-restricted (token-id uint) (region (string-ascii 10)))
    (let ((restricted-regions (get-restricted-regions token-id)))
        (is-some (index-of restricted-regions region))
    )
)

;; Get usage attempt history
(define-read-only (get-usage-attempt (token-id uint) (user principal) (region (string-ascii 10)))
    (map-get? usage-attempts {token-id: token-id, user: user, region: region})
)

;; Get current token ID counter
(define-read-only (get-current-token-id)
    (var-get token-id-nonce)
)
