;; IP Dispute Resolution Smart Contract
;; Provides decentralized arbitration for intellectual property disputes

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DISPUTE-NOT-FOUND (err u101))
(define-constant ERR-DISPUTE-ALREADY-RESOLVED (err u102))
(define-constant ERR-NOT-INVOLVED-PARTY (err u103))
(define-constant ERR-NOT-ARBITRATOR (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-INSUFFICIENT-ARBITRATORS (err u106))
(define-constant ERR-INVALID-DECISION (err u107))

;; Dispute statuses
(define-constant STATUS-CREATED u0)
(define-constant STATUS-IN-PROGRESS u1)
(define-constant STATUS-RESOLVED u2)

;; Decision types
(define-constant DECISION-FAVOR-PLAINTIFF u0)
(define-constant DECISION-FAVOR-DEFENDANT u1)
(define-constant DECISION-SPLIT u2)

;; Data Variables
(define-data-var dispute-counter uint u0)
(define-data-var arbitration-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var min-arbitrators uint u3)

;; Data Maps
(define-map disputes
  uint
  {
    plaintiff: principal,
    defendant: principal,
    involved-parties: (list 10 principal),
    dispute-details: (string-ascii 500),
    status: uint,
    arbitrators: (list 5 principal),
    created-at: uint,
    resolved-at: (optional uint),
    resolution: (optional (string-ascii 300)),
    winning-party: (optional principal),
    fee-paid: uint
  }
)

(define-map arbitrator-registry
  principal
  {
    is-active: bool,
    reputation-score: uint,
    cases-handled: uint,
    successful-resolutions: uint
  }
)

(define-map dispute-votes
  {dispute-id: uint, arbitrator: principal}
  {
    decision: uint,
    reasoning: (string-ascii 200),
    voted-at: uint
  }
)

(define-map arbitrator-assignments
  {dispute-id: uint, arbitrator: principal}
  bool
)

;; Read-only functions
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

(define-read-only (get-arbitrator-info (arbitrator principal))
  (map-get? arbitrator-registry arbitrator)
)

(define-read-only (get-dispute-vote (dispute-id uint) (arbitrator principal))
  (map-get? dispute-votes {dispute-id: dispute-id, arbitrator: arbitrator})
)

(define-read-only (is-arbitrator-assigned (dispute-id uint) (arbitrator principal))
  (default-to false (map-get? arbitrator-assignments {dispute-id: dispute-id, arbitrator: arbitrator}))
)

(define-read-only (get-dispute-counter)
  (var-get dispute-counter)
)

(define-read-only (get-arbitration-fee)
  (var-get arbitration-fee)
)

(define-read-only (is-involved-party (dispute-id uint) (party principal))
  (match (map-get? disputes dispute-id)
    dispute-data
    (or 
      (is-eq party (get plaintiff dispute-data))
      (is-eq party (get defendant dispute-data))
      (is-some (index-of (get involved-parties dispute-data) party))
    )
    false
  )
)

;; Private functions
(define-private (select-arbitrators (dispute-id uint))
  (let ((active-arbitrators (get-active-arbitrators)))
    (if (>= (len active-arbitrators) (var-get min-arbitrators))
      (assign-arbitrators-to-dispute dispute-id (unwrap-panic (slice? active-arbitrators u0 (var-get min-arbitrators))))
      ERR-INSUFFICIENT-ARBITRATORS
    )
  )
)

(define-private (get-active-arbitrators)
  ;; Get list of active arbitrators from the registry
  (filter is-arbitrator-active (get-all-registered-arbitrators))
)

(define-private (get-all-registered-arbitrators)
  ;; This is a simplified approach - in a real implementation, you'd maintain a list
  ;; For now, we'll return a hardcoded list of potential arbitrators
  (list 
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7
    'SP2KAF9RF86PVX3NEE27DFV1CQX0T4WGR41X3S45C
    'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9
  )
)

(define-private (is-arbitrator-active (arbitrator principal))
  (match (map-get? arbitrator-registry arbitrator)
    arbitrator-data (get is-active arbitrator-data)
    false
  )
)

(define-private (assign-arbitrators-to-dispute (dispute-id uint) (arbitrators (list 5 principal)))
  ;; First assign each arbitrator individually
  (match (fold assign-single-arbitrator arbitrators (ok dispute-id))
    success-id 
    ;; If all assignments succeeded, update the dispute record
    (if (is-some (map-get? disputes dispute-id))
      (begin
        (map-set disputes dispute-id
          (merge 
            (unwrap-panic (map-get? disputes dispute-id))
            {arbitrators: arbitrators}
          )
        )
        (ok dispute-id)
      )
      ERR-DISPUTE-NOT-FOUND
    )
    ;; If any assignment failed, return the error
    error-code (err error-code)
  )
)

(define-private (assign-single-arbitrator (arbitrator principal) (result (response uint uint)))
  (match result
    dispute-id
    (begin
      (map-set arbitrator-assignments 
        {dispute-id: dispute-id, arbitrator: arbitrator} 
        true
      )
      (ok dispute-id)
    )
    error-val (err error-val)
  )
)


(define-private (count-votes (dispute-id uint))
  (match (map-get? disputes dispute-id)
    dispute-data
    (let ((arbitrators (get arbitrators dispute-data)))
      (fold count-arbitrator-vote-for-dispute 
            arbitrators 
            {dispute-id: dispute-id, favor-plaintiff: u0, favor-defendant: u0, split: u0})
    )
    ;; If dispute doesn't exist, return empty vote counts with matching structure
    {dispute-id: dispute-id, favor-plaintiff: u0, favor-defendant: u0, split: u0}
  )
)

(define-private (count-arbitrator-vote-for-dispute 
  (arbitrator principal) 
  (vote-counts {dispute-id: uint, favor-plaintiff: uint, favor-defendant: uint, split: uint}))
  (let ((dispute-id (get dispute-id vote-counts)))
    (match (map-get? dispute-votes {dispute-id: dispute-id, arbitrator: arbitrator})
      vote-data
      (let ((decision (get decision vote-data)))
        (if (is-eq decision DECISION-FAVOR-PLAINTIFF)
          (merge vote-counts {favor-plaintiff: (+ (get favor-plaintiff vote-counts) u1)})
          (if (is-eq decision DECISION-FAVOR-DEFENDANT)
            (merge vote-counts {favor-defendant: (+ (get favor-defendant vote-counts) u1)})
            (merge vote-counts {split: (+ (get split vote-counts) u1)})
          )
        )
      )
      vote-counts
    )
  )
)

;; Public functions

;; Register as an arbitrator
(define-public (register-arbitrator)
  (begin
    (map-set arbitrator-registry tx-sender
      {
        is-active: true,
        reputation-score: u100,
        cases-handled: u0,
        successful-resolutions: u0
      }
    )
    (ok true)
  )
)

;; Start a new dispute
(define-public (start-dispute 
  (defendant principal)
  (involved-parties (list 10 principal))
  (dispute-details (string-ascii 500))
)
  (let (
    (dispute-id (+ (var-get dispute-counter) u1))
    (fee (var-get arbitration-fee))
  )
    ;; Transfer arbitration fee
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    
    ;; Create dispute record
    (map-set disputes dispute-id
      {
        plaintiff: tx-sender,
        defendant: defendant,
        involved-parties: involved-parties,
        dispute-details: dispute-details,
        status: STATUS-CREATED,
        arbitrators: (list),
        created-at: stacks-block-height,
        resolved-at: none,
        resolution: none,
        winning-party: none,
        fee-paid: fee
      }
    )
    
    ;; Update counter
    (var-set dispute-counter dispute-id)
    
    ;; Assign arbitrators
    (try! (select-arbitrators dispute-id))
    
    ;; Update status to in-progress
    (map-set disputes dispute-id
      (merge 
        (unwrap-panic (map-get? disputes dispute-id))
        {status: STATUS-IN-PROGRESS}
      )
    )
    
    (ok dispute-id)
  )
)

;; Submit arbitrator vote
(define-public (submit-vote 
  (dispute-id uint)
  (decision uint)
  (reasoning (string-ascii 200))
)
  (let (
    (dispute-data (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
  )
    ;; Check if caller is assigned arbitrator
    (asserts! (is-arbitrator-assigned dispute-id tx-sender) ERR-NOT-ARBITRATOR)
    
    ;; Check if dispute is still in progress
    (asserts! (is-eq (get status dispute-data) STATUS-IN-PROGRESS) ERR-DISPUTE-ALREADY-RESOLVED)
    
    ;; Check if arbitrator hasn't voted yet
    (asserts! (is-none (map-get? dispute-votes {dispute-id: dispute-id, arbitrator: tx-sender})) ERR-ALREADY-VOTED)
    
    ;; Validate decision
    (asserts! (or (is-eq decision DECISION-FAVOR-PLAINTIFF) 
                  (is-eq decision DECISION-FAVOR-DEFENDANT) 
                  (is-eq decision DECISION-SPLIT)) ERR-INVALID-DECISION)
    
    ;; Record vote
    (map-set dispute-votes 
      {dispute-id: dispute-id, arbitrator: tx-sender}
      {
        decision: decision,
        reasoning: reasoning,
        voted-at: stacks-block-height
      }
    )
    
    ;; Check if all arbitrators have voted and resolve if so
    (try! (attempt-resolution dispute-id))
    
    (ok true)
  )
)

;; Attempt to resolve dispute if all votes are in
(define-public (attempt-resolution (dispute-id uint))
  (let (
    (dispute-data (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
    (vote-counts (count-votes dispute-id))
    (total-arbitrators (len (get arbitrators dispute-data)))
  )
    ;; Check if all arbitrators have voted
    (if (is-eq (+ (+ (get favor-plaintiff vote-counts) (get favor-defendant vote-counts)) (get split vote-counts)) total-arbitrators)
      (let (
        (winning-decision 
          (if (> (get favor-plaintiff vote-counts) (get favor-defendant vote-counts))
            (if (> (get favor-plaintiff vote-counts) (get split vote-counts))
              DECISION-FAVOR-PLAINTIFF
              DECISION-SPLIT
            )
            (if (> (get favor-defendant vote-counts) (get split vote-counts))
              DECISION-FAVOR-DEFENDANT
              DECISION-SPLIT
            )
          )
        )
        (winning-party 
          (if (is-eq winning-decision DECISION-FAVOR-PLAINTIFF)
            (some (get plaintiff dispute-data))
            (if (is-eq winning-decision DECISION-FAVOR-DEFENDANT)
              (some (get defendant dispute-data))
              none
            )
          )
        )
      )
        ;; Update dispute with resolution
        (map-set disputes dispute-id
          (merge dispute-data
            {
              status: STATUS-RESOLVED,
              resolved-at: (some stacks-block-height),
              winning-party: winning-party,
              resolution: (some "Dispute resolved through arbitration")
            }
          )
        )
        
        ;; Distribute fees to arbitrators
        (try! (distribute-arbitration-fees dispute-id))
        
        (ok true)
      )
      (ok false) ;; Not all votes are in yet
    )
  )
)

;; Distribute arbitration fees to arbitrators
(define-private (distribute-arbitration-fees (dispute-id uint))
  (let (
    (dispute-data (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
    (total-fee (get fee-paid dispute-data))
    (arbitrators (get arbitrators dispute-data))
    (fee-per-arbitrator (/ total-fee (len arbitrators)))
  )
    (fold distribute-fee-to-arbitrator arbitrators (ok fee-per-arbitrator))
  )
)

(define-private (distribute-fee-to-arbitrator (arbitrator principal) (fee-result (response uint uint)))
  (match fee-result
    fee-amount
    (begin
      (try! (as-contract (stx-transfer? fee-amount tx-sender arbitrator)))
      (ok fee-amount)
    )
    error-val (err error-val)
  )
)

;; Admin functions
(define-public (set-arbitration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set arbitration-fee new-fee)
    (ok true)
  )
)

(define-public (set-min-arbitrators (new-min uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set min-arbitrators new-min)
    (ok true)
  )
)

;; Emergency functions
(define-public (emergency-resolve-dispute 
  (dispute-id uint)
  (winning-party (optional principal))
  (resolution (string-ascii 300))
)
  (let (
    (dispute-data (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (not (is-eq (get status dispute-data) STATUS-RESOLVED)) ERR-DISPUTE-ALREADY-RESOLVED)
    
    (map-set disputes dispute-id
      (merge dispute-data
        {
          status: STATUS-RESOLVED,
          resolved-at: (some stacks-block-height),
          winning-party: winning-party,
          resolution: (some resolution)
        }
      )
    )
    
    (ok true)
  )
)