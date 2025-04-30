
;; title: ip-stamping
;; version:
;; summary:
;; description:

;; IP Timestamping & Proof of Ownership Contract

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-found (err u102))

;; Define the data structure for IP registration
(define-map ip-registrations
  { ip-id: uint }
  {
    creator: principal,
    metadata: (string-utf8 500),
    timestamp: uint
  }
)

;; Define a variable to keep track of the last IP ID
(define-data-var last-ip-id uint u0)

;; Register new IP
(define-public (register-ip (metadata (string-utf8 500)))
  (let
    (
      (new-ip-id (+ (var-get last-ip-id) u1))
      (caller tx-sender)
    )
    (asserts! (is-none (map-get? ip-registrations { ip-id: new-ip-id })) err-already-registered)
    (map-set ip-registrations
      { ip-id: new-ip-id }
      {
        creator: caller,
        metadata: metadata,
        timestamp: block-height
      }
    )
    (var-set last-ip-id new-ip-id)
    (ok new-ip-id)
  )
)

;; Get IP registration details
(define-read-only (get-ip-details (ip-id uint))
  (match (map-get? ip-registrations { ip-id: ip-id })
    registration (ok registration)
    err-not-found
  )
)

;; Check if an IP is registered
(define-read-only (is-ip-registered (ip-id uint))
  (is-some (map-get? ip-registrations { ip-id: ip-id }))
)

;; Get the total number of registered IPs
(define-read-only (get-total-registrations)
  (ok (var-get last-ip-id))
)

;; Verify the creator of an IP
(define-read-only (verify-ip-creator (ip-id uint) (creator principal))
  (match (map-get? ip-registrations { ip-id: ip-id })
    registration (ok (is-eq (get creator registration) creator))
    err-not-found
  )
)

;; Update IP metadata (only by the original creator)
(define-public (update-ip-metadata (ip-id uint) (new-metadata (string-utf8 500)))
  (match (map-get? ip-registrations { ip-id: ip-id })
    registration 
    (begin
      (asserts! (is-eq tx-sender (get creator registration)) err-owner-only)
      (ok (map-set ip-registrations
        { ip-id: ip-id }
        (merge registration { metadata: new-metadata })
      ))
    )
    err-not-found
  )
)

;; Initialize the contract
(begin
  (print "IP Timestamping & Proof of Ownership Contract initialized")
)