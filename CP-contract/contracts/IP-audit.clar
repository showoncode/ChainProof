;; IP Audit Trail & Transparency Smart Contract
;; Provides immutable transaction history for IP tokens

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u404))
(define-constant err-invalid-token (err u400))
(define-constant err-unauthorized (err u401))

;; Data Variables
(define-data-var next-token-id uint u1)

;; Transaction Types
(define-constant TX-REGISTRATION u1)
(define-constant TX-TRANSFER u2)
(define-constant TX-LICENSE-GRANT u3)
(define-constant TX-LICENSE-REVOKE u4)
(define-constant TX-METADATA-UPDATE u5)

;; Data Maps

;; Core IP Token Information
(define-map ip-tokens
  { token-id: uint }
  {
    owner: principal,
    creator: principal,
    title: (string-ascii 256),
    description: (string-ascii 512),
    ip-type: (string-ascii 64),
    created-at: uint,
    active: bool
  }
)

;; Transaction History - Each transaction gets a unique sequence number
(define-map ip-transactions
  { token-id: uint, sequence: uint }
  {
    transaction-type: uint,
    from-address: (optional principal),
    to-address: (optional principal),
    timestamp: uint,
    block-height: uint,
    tx-hash: (buff 32),
    metadata: (string-ascii 512),
    gas-used: uint
  }
)

;; Track transaction count per token
(define-map token-transaction-count
  { token-id: uint }
  { count: uint }
)

;; License tracking for audit purposes
(define-map ip-licenses
  { token-id: uint, licensee: principal }
  {
    granted-at: uint,
    expires-at: (optional uint),
    license-type: (string-ascii 64),
    active: bool,
    terms: (string-ascii 512)
  }
)

;; Helper Functions

;; Get next transaction sequence number for a token
(define-private (get-next-sequence (token-id uint))
  (let ((current-count (default-to u0 
    (get count (map-get? token-transaction-count { token-id: token-id })))))
    (+ current-count u1)
  )
)

;; Update transaction count for a token
(define-private (increment-transaction-count (token-id uint))
  (let ((current-count (default-to u0 
    (get count (map-get? token-transaction-count { token-id: token-id })))))
    (map-set token-transaction-count 
      { token-id: token-id }
      { count: (+ current-count u1) })
  )
)

;; Record a transaction in the audit trail
(define-private (record-transaction 
  (token-id uint) 
  (tx-type uint) 
  (from-addr (optional principal)) 
  (to-addr (optional principal))
  (metadata (string-ascii 512)))
  (let ((sequence (get-next-sequence token-id)))
    (map-set ip-transactions
      { token-id: token-id, sequence: sequence }
      {
        transaction-type: tx-type,
        from-address: from-addr,
        to-address: to-addr,
        timestamp: (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))),
        block-height: stacks-block-height,
        tx-hash: (unwrap-panic (get-stacks-block-info? id-header-hash (- stacks-block-height u1))),
        metadata: metadata,
        gas-used: u0 ;; Simplified - in practice you'd calculate actual gas
      })
    (increment-transaction-count token-id)
    (ok sequence)
  )
)

;; Public Functions

;; Register new IP token
(define-public (register-ip 
  (title (string-ascii 256))
  (description (string-ascii 512))
  (ip-type (string-ascii 64)))
  (let ((token-id (var-get next-token-id)))
    (map-set ip-tokens
      { token-id: token-id }
      {
        owner: tx-sender,
        creator: tx-sender,
        title: title,
        description: description,
        ip-type: ip-type,
        created-at: stacks-block-height,
        active: true
      })
    
    
    
    (var-set next-token-id (+ token-id u1))
    (ok token-id)
  )
)

;; Transfer IP ownership
(define-public (transfer-ip (token-id uint) (to principal))
  (let ((token-info (unwrap! (map-get? ip-tokens { token-id: token-id }) err-not-found)))
    (asserts! (is-eq (get owner token-info) tx-sender) err-unauthorized)
    (asserts! (get active token-info) err-invalid-token)
    
    ;; Update ownership
    (map-set ip-tokens
      { token-id: token-id }
      (merge token-info { owner: to }))
    
    
    
    (ok true)
  )
)

;; Grant license
(define-public (grant-license 
  (token-id uint) 
  (licensee principal)
  (license-type (string-ascii 64))
  (expires-at (optional uint))
  (terms (string-ascii 512)))
  (let ((token-info (unwrap! (map-get? ip-tokens { token-id: token-id }) err-not-found)))
    (asserts! (is-eq (get owner token-info) tx-sender) err-unauthorized)
    (asserts! (get active token-info) err-invalid-token)
    
    ;; Create license
    (map-set ip-licenses
      { token-id: token-id, licensee: licensee }
      {
        granted-at: stacks-block-height,
        expires-at: expires-at,
        license-type: license-type,
        active: true,
        terms: terms
      })
    
    
    
    (ok true)
  )
)

;; Revoke license
(define-public (revoke-license (token-id uint) (licensee principal))
  (let ((token-info (unwrap! (map-get? ip-tokens { token-id: token-id }) err-not-found))
        (license-info (unwrap! (map-get? ip-licenses { token-id: token-id, licensee: licensee }) err-not-found)))
    (asserts! (is-eq (get owner token-info) tx-sender) err-unauthorized)
    (asserts! (get active license-info) err-invalid-token)
    
    ;; Deactivate license
    (map-set ip-licenses
      { token-id: token-id, licensee: licensee }
      (merge license-info { active: false }))
    
    
    (ok true)
  )
)

;; Read-only Functions

;; Get complete IP history (equivalent to getIPHistory function)
(define-read-only (get-ip-history (token-id uint))
  (let ((token-info (map-get? ip-tokens { token-id: token-id }))
        (tx-count (default-to u0 
          (get count (map-get? token-transaction-count { token-id: token-id })))))
    (if (is-some token-info)
      (ok {
        token-info: token-info,
        transaction-count: tx-count,
        transactions: (get-transactions-range token-id u1 tx-count)
      })
      err-not-found
    )
  )
)

;; Get transactions for a token within a range
(define-read-only (get-transactions-range (token-id uint) (start uint) (end uint))
  (map get-single-transaction 
    (generate-sequence-list start end token-id))
)

;; Helper to get a single transaction
(define-read-only (get-single-transaction (params { sequence: uint, token-id: uint }))
  (map-get? ip-transactions { token-id: (get token-id params), sequence: (get sequence params) })
)

;; Generate list of sequence numbers (simplified version)
(define-read-only (generate-sequence-list (start uint) (end uint) (token-id uint))
  (if (<= start end)
    (list { sequence: start, token-id: token-id })
    (list)
  )
)

;; Get specific transaction by sequence
(define-read-only (get-transaction (token-id uint) (sequence uint))
  (map-get? ip-transactions { token-id: token-id, sequence: sequence })
)

;; Get token information
(define-read-only (get-token-info (token-id uint))
  (map-get? ip-tokens { token-id: token-id })
)

;; Get transaction count for a token
(define-read-only (get-transaction-count (token-id uint))
  (default-to u0 
    (get count (map-get? token-transaction-count { token-id: token-id })))
)

;; Get license information
(define-read-only (get-license-info (token-id uint) (licensee principal))
  (map-get? ip-licenses { token-id: token-id, licensee: licensee })
)


;; Helper function for filtering transactions by type
(define-private (is-matching-type (tx (optional { transaction-type: uint, from-address: (optional principal), to-address: (optional principal), timestamp: uint, block-height: uint, tx-hash: (buff 32), metadata: (string-ascii 512), gas-used: uint })) (target-type uint))
  (match tx
    some-tx (is-eq (get transaction-type some-tx) target-type)
    false
  )
)

;; Administrative Functions

;; Update IP metadata (only owner)
(define-public (update-metadata 
  (token-id uint) 
  (new-description (string-ascii 512)))
  (let ((token-info (unwrap! (map-get? ip-tokens { token-id: token-id }) err-not-found)))
    (asserts! (is-eq (get owner token-info) tx-sender) err-unauthorized)
    
    ;; Update metadata
    (map-set ip-tokens
      { token-id: token-id }
      (merge token-info { description: new-description }))
    
    
    (ok true)
  )
)

;; Deactivate IP token (only owner)
(define-public (deactivate-token (token-id uint))
  (let ((token-info (unwrap! (map-get? ip-tokens { token-id: token-id }) err-not-found)))
    (asserts! (is-eq (get owner token-info) tx-sender) err-unauthorized)
    
    (map-set ip-tokens
      { token-id: token-id }
      (merge token-info { active: false }))
    
    (ok true)
  )
)