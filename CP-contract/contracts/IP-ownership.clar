;; IP Ownership Verification Contract
;; This contract allows users to register and verify IP ownership and licensing information

;; Define data maps for storing IP ownership and licensing information
(define-map ip-registry
  { ip-id: (string-utf8 128) }
  {
    owner: principal,
    creation-time: uint,
    license-type: (string-utf8 64),
    metadata: (string-utf8 256),
    is-transferable: bool
  }
)

;; Define map for tracking IP transfer history
(define-map ip-transfer-history
  { ip-id: (string-utf8 128), transfer-index: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    transfer-time: uint
  }
)

;; Define map for tracking transfer counts per IP
(define-map ip-transfer-count
  { ip-id: (string-utf8 128) }
  { count: uint }
)

;; Error codes
(define-constant ERR-NOT-FOUND u1)
(define-constant ERR-UNAUTHORIZED u2)
(define-constant ERR-ALREADY-EXISTS u3)
(define-constant ERR-NOT-TRANSFERABLE u4)

;; Register new IP
(define-public (register-ip (ip-id (string-utf8 128)) 
                           (license-type (string-utf8 64)) 
                           (metadata (string-utf8 256))
                           (is-transferable bool))
  (let ((existing-ip (map-get? ip-registry { ip-id: ip-id })))
    (if (is-some existing-ip)
      (err ERR-ALREADY-EXISTS)
      (begin
        (map-set ip-registry
          { ip-id: ip-id }
          {
            owner: tx-sender,
            creation-time: stacks-block-height,
            license-type: license-type,
            metadata: metadata,
            is-transferable: is-transferable
          }
        )
        (map-set ip-transfer-count
          { ip-id: ip-id }
          { count: u0 }
        )
        (ok true)
      )
    )
  )
)

;; Verify ownership of IP
(define-public (verify-ownership (owner principal) (ip-id (string-utf8 128)))
  (let ((ip-data (map-get? ip-registry { ip-id: ip-id })))
    (if (is-some ip-data)
      (ok (is-eq owner (get owner (unwrap! ip-data (err ERR-NOT-FOUND)))))
      (err ERR-NOT-FOUND)
    )
  )
)

;; Get IP details
(define-read-only (get-ip-details (ip-id (string-utf8 128)))
  (let ((ip-data (map-get? ip-registry { ip-id: ip-id })))
    (if (is-some ip-data)
      (ok (unwrap! ip-data (err ERR-NOT-FOUND)))
      (err ERR-NOT-FOUND)
    )
  )
)

;; Transfer IP ownership
(define-public (transfer-ip (ip-id (string-utf8 128)) (new-owner principal))
  (let (
    (ip-data (map-get? ip-registry { ip-id: ip-id }))
    (transfer-count-data (map-get? ip-transfer-count { ip-id: ip-id }))
  )
    (if (is-some ip-data)
      (let (
        (unwrapped-ip-data (unwrap! ip-data (err ERR-NOT-FOUND)))
        (unwrapped-count (unwrap! transfer-count-data (err ERR-NOT-FOUND)))
        (current-count (get count unwrapped-count))
      )
        (if (is-eq tx-sender (get owner unwrapped-ip-data))
          (if (get is-transferable unwrapped-ip-data)
            (begin
              ;; Update ownership
              (map-set ip-registry
                { ip-id: ip-id }
                (merge unwrapped-ip-data { owner: new-owner })
              )
              
              ;; Record transfer in history
              (map-set ip-transfer-history
                { ip-id: ip-id, transfer-index: current-count }
                {
                  previous-owner: tx-sender,
                  new-owner: new-owner,
                  transfer-time: stacks-block-height
                }
              )
              
              ;; Update transfer count
              (map-set ip-transfer-count
                { ip-id: ip-id }
                { count: (+ current-count u1) }
              )
              
              (ok true)
            )
            (err ERR-NOT-TRANSFERABLE)
          )
          (err ERR-UNAUTHORIZED)
        )
      )
      (err ERR-NOT-FOUND)
    )
  )
)

;; Get transfer history for an IP
(define-read-only (get-transfer-history (ip-id (string-utf8 128)) (index uint))
  (let ((history-entry (map-get? ip-transfer-history { ip-id: ip-id, transfer-index: index })))
    (if (is-some history-entry)
      (ok (unwrap! history-entry (err ERR-NOT-FOUND)))
      (err ERR-NOT-FOUND)
    )
  )
)

;; Verify license compatibility
(define-public (verify-license-compatibility (ip-id (string-utf8 128)) (requested-usage (string-utf8 64)))
  (let ((ip-data (map-get? ip-registry { ip-id: ip-id })))
    (if (is-some ip-data)
      (let ((license-type (get license-type (unwrap! ip-data (err ERR-NOT-FOUND)))))
        ;; This is a simplified check - in a real implementation, you would have more complex logic
        ;; to determine if the requested usage is compatible with the license type
        (ok (is-eq license-type requested-usage))
      )
      (err ERR-NOT-FOUND)
    )
  )
)