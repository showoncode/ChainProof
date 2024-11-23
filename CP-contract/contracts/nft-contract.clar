
;; title: nft-contract
;; version:
;; summary:
;; description:

;; NFT-based Licensing & Contracts

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-token-not-found (err u102))
(define-constant err-unauthorized (err u103))

;; Define the NFT token
(define-non-fungible-token ip-license uint)

;; Define maps for token data
(define-map token-licenses 
  { token-id: uint } 
  { 
    owner: principal,
    license-terms: (string-utf8 1000),
    is-active: bool
  }
)

;; Define variable for last token ID
(define-data-var last-token-id uint u0)

;; Mint new NFT license
(define-public (mint-nft (owner principal) (license-terms (string-utf8 1000)))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (nft-mint? ip-license token-id owner))
    (map-set token-licenses
      { token-id: token-id }
      {
        owner: owner,
        license-terms: license-terms,
        is-active: true
      }
    )
    (var-set last-token-id token-id)
    (ok token-id)
  )
)

;; Transfer NFT license
(define-public (transfer-nft (token-id uint) (sender principal) (recipient principal))
  (let
    (
      (license-data (unwrap! (map-get? token-licenses { token-id: token-id }) err-token-not-found))
    )
    (asserts! (is-eq tx-sender sender) err-unauthorized)
    (asserts! (is-eq (get owner license-data) sender) err-not-token-owner)
    (try! (nft-transfer? ip-license token-id sender recipient))
    (map-set token-licenses
      { token-id: token-id }
      (merge license-data { owner: recipient })
    )
    (ok true)
  )
)

;; Get license terms
(define-read-only (get-license-terms (token-id uint))
  (match (map-get? token-licenses { token-id: token-id })
    license-data (ok (get license-terms license-data))
    err-token-not-found
  )
)

;; Verify license ownership
(define-read-only (verify-license-owner (token-id uint) (owner principal))
  (match (map-get? token-licenses { token-id: token-id })
    license-data (ok (and (is-eq (get owner license-data) owner) (get is-active license-data)))
    err-token-not-found
  )
)

;; Update license terms (only by contract owner)
(define-public (update-license-terms (token-id uint) (new-terms (string-utf8 1000)))
  (let
    (
      (license-data (unwrap! (map-get? token-licenses { token-id: token-id }) err-token-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set token-licenses
      { token-id: token-id }
      (merge license-data { license-terms: new-terms })
    ))
  )
)

;; Revoke license (only by contract owner)
(define-public (revoke-license (token-id uint))
  (let
    (
      (license-data (unwrap! (map-get? token-licenses { token-id: token-id }) err-token-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set token-licenses
      { token-id: token-id }
      (merge license-data { is-active: false })
    ))
  )
)

;; Get total number of licenses issued
(define-read-only (get-total-licenses)
  (ok (var-get last-token-id))
)

;; Initialize the contract
(begin
  (print "NFT-based Licensing & Contracts initialized")
)

