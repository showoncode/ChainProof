;; automated-contract-enforcement.clar
;; Automated enforcement of IP licenses, terms of use, and contracts

;; =============================================================================
;; CONSTANTS AND ERROR CODES
;; =============================================================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u2000))
(define-constant ERR_TOKEN_NOT_FOUND (err u2001))
(define-constant ERR_LICENSE_EXPIRED (err u2002))
(define-constant ERR_ACTION_NOT_PERMITTED (err u2003))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u2004))
(define-constant ERR_USER_SUSPENDED (err u2005))
(define-constant ERR_INVALID_LICENSE_TYPE (err u2006))
(define-constant ERR_USAGE_LIMIT_EXCEEDED (err u2007))
(define-constant ERR_TERRITORY_RESTRICTION (err u2008))
(define-constant ERR_INVALID_ACTION (err u2009))
(define-constant ERR_PENALTY_ALREADY_APPLIED (err u2010))
(define-constant ERR_LICENSE_REVOKED (err u2011))
(define-constant ERR_COMPLIANCE_VIOLATION (err u2012))

;; License types
(define-constant LICENSE_TYPE_BASIC u0)
(define-constant LICENSE_TYPE_COMMERCIAL u1)
(define-constant LICENSE_TYPE_EXCLUSIVE u2)
(define-constant LICENSE_TYPE_ROYALTY_FREE u3)
(define-constant LICENSE_TYPE_SUBSCRIPTION u4)

;; Action types
(define-constant ACTION_VIEW u0)
(define-constant ACTION_DOWNLOAD u1)
(define-constant ACTION_MODIFY u2)
(define-constant ACTION_DISTRIBUTE u3)
(define-constant ACTION_COMMERCIAL_USE u4)
(define-constant ACTION_SUBLICENSE u5)

;; License status
(define-constant LICENSE_STATUS_ACTIVE u0)
(define-constant LICENSE_STATUS_EXPIRED u1)
(define-constant LICENSE_STATUS_SUSPENDED u2)
(define-constant LICENSE_STATUS_REVOKED u3)

;; =============================================================================
;; DATA MAPS AND VARIABLES
;; =============================================================================

;; Token metadata and ownership
(define-map tokens
  { token-id: uint }
  {
    owner: principal,
    creator: principal,
    title: (string-utf8 256),
    description: (string-utf8 512),
    created-at: uint,
    total-licenses-issued: uint,
    royalty-percentage: uint, ;; percentage * 100 (e.g., 250 = 2.5%)
    is-active: bool
  }
)

;; License definitions and terms
(define-map license-templates
  { license-id: uint }
  {
    license-type: uint,
    name: (string-utf8 128),
    description: (string-utf8 512),
    base-price: uint,
    duration-blocks: uint, ;; 0 for perpetual
    max-usage-count: uint, ;; 0 for unlimited
    allowed-actions: (list 10 uint),
    restricted-territories: (list 20 (string-ascii 3)), ;; country codes
    commercial-allowed: bool,
    sublicense-allowed: bool,
    modification-allowed: bool,
    attribution-required: bool,
    created-by: principal,
    is-active: bool
  }
)

;; User licenses for specific tokens
(define-map user-licenses
  { token-id: uint, user: principal, license-id: uint }
  {
    granted-at: uint,
    expires-at: uint, ;; 0 for perpetual
    payment-amount: uint,
    usage-count: uint,
    max-usage: uint,
    status: uint,
    territory-restrictions: (list 20 (string-ascii 3)),
    custom-terms: (optional (string-utf8 512)),
    last-used: uint,
    penalty-count: uint
  }
)

;; Action permissions matrix
(define-map action-permissions
  { token-id: uint, license-id: uint, action-type: uint }
  {
    is-permitted: bool,
    requires-payment: bool,
    payment-per-use: uint,
    daily-limit: uint,
    territory-restricted: bool,
    compliance-required: bool
  }
)

;; User compliance and violation tracking
(define-map user-compliance
  { user: principal }
  {
    total-violations: uint,
    last-violation: uint,
    suspension-count: uint,
    is-suspended: bool,
    suspended-until: uint,
    reputation-score: uint, ;; 0-1000
    total-licenses-held: uint
  }
)

;; Enforcement actions log
(define-map enforcement-actions
  { action-id: uint }
  {
    token-id: uint,
    user: principal,
    action-type: uint,
    enforcement-type: (string-ascii 32), ;; "penalty", "suspension", "revocation"
    reason: (string-utf8 256),
    penalty-amount: uint,
    executed-at: uint,
    executed-by: principal
  }
)

;; Usage tracking for analytics and compliance
(define-map usage-logs
  { log-id: uint }
  {
    token-id: uint,
    user: principal,
    license-id: uint,
    action-performed: uint,
    timestamp: uint,
    location: (optional (string-ascii 3)), ;; country code
    ip-hash: (optional (buff 32)),
    was-authorized: bool
  }
)

;; Revenue tracking for royalties
(define-map revenue-tracking
  { token-id: uint, period: uint } ;; period = block-height / 10080 (weekly)
  {
    total-revenue: uint,
    license-fees: uint,
    usage-fees: uint,
    penalty-fees: uint,
    royalties-paid: uint,
    transactions-count: uint
  }
)

;; Counter variables
(define-data-var next-license-template-id uint u1)
(define-data-var next-enforcement-action-id uint u1)
(define-data-var next-usage-log-id uint u1)

;; Global enforcement settings
(define-data-var enforcement-enabled bool true)
(define-data-var default-penalty-rate uint u100) ;; per violation
(define-data-var max-violations-before-suspension uint u5)
(define-data-var suspension-duration-blocks uint u14400) ;; ~10 days

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

(define-private (get-current-block-height)
  stacks-block-height
)

(define-private (is-license-valid (token-id uint) (user principal) (license-id uint))
  (match (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id })
    license
    (let
      (
        (current-block (get-current-block-height))
        (expires-at (get expires-at license))
        (status (get status license))
      )
      (and 
        (is-eq status LICENSE_STATUS_ACTIVE)
        (or (is-eq expires-at u0) (> expires-at current-block))))
    false)
)

(define-private (check-territory-restriction (user-location (string-ascii 3)) (restricted-territories (list 20 (string-ascii 3))))
  (not (is-some (index-of restricted-territories user-location)))
)

(define-private (check-usage-limits (token-id uint) (user principal) (license-id uint))
  (match (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id })
    license
    (let
      (
        (usage-count (get usage-count license))
        (max-usage (get max-usage license))
      )
      (or (is-eq max-usage u0) (< usage-count max-usage)))
    false)
)

(define-private (increment-usage-count (token-id uint) (user principal) (license-id uint))
  (match (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id })
    license
    (let
      (
        (current-block (get-current-block-height))
        (new-count (+ (get usage-count license) u1))
      )
      (map-set user-licenses
        { token-id: token-id, user: user, license-id: license-id }
        (merge license {
          usage-count: new-count,
          last-used: current-block
        })))
    false)
)

(define-private (apply-penalty (user principal) (penalty-amount uint) (reason (string-utf8 256)))
  (let
    (
      (current-compliance (default-to 
        { total-violations: u0, last-violation: u0, suspension-count: u0, 
          is-suspended: false, suspended-until: u0, reputation-score: u1000, 
          total-licenses-held: u0 }
        (map-get? user-compliance { user: user })))
      (new-violations (+ (get total-violations current-compliance) u1))
      (new-reputation (if (> (get reputation-score current-compliance) u50)
                        (- (get reputation-score current-compliance) u50)
                        u0))
      (current-block (get-current-block-height))
    )
    (map-set user-compliance
      { user: user }
      (merge current-compliance {
        total-violations: new-violations,
        last-violation: current-block,
        reputation-score: new-reputation
      }))
    
    ;; Check if suspension is needed
    (if (>= new-violations (var-get max-violations-before-suspension))
      (suspend-user user)
      true)
  )
)

(define-private (suspend-user (user principal))
  (let
    (
      (current-compliance (unwrap-panic (map-get? user-compliance { user: user })))
      (current-block (get-current-block-height))
      (suspension-end (+ current-block (var-get suspension-duration-blocks)))
    )
    (map-set user-compliance
      { user: user }
      (merge current-compliance {
        is-suspended: true,
        suspended-until: suspension-end,
        suspension-count: (+ (get suspension-count current-compliance) u1)
      }))
  )
)

(define-private (log-enforcement-action 
  (token-id uint) 
  (user principal) 
  (action-type uint)
  (enforcement-type (string-ascii 32))
  (reason (string-utf8 256))
  (penalty-amount uint))
  (let
    (
      (action-id (var-get next-enforcement-action-id))
      (current-block (get-current-block-height))
    )
    (map-set enforcement-actions
      { action-id: action-id }
      {
        token-id: token-id,
        user: user,
        action-type: action-type,
        enforcement-type: enforcement-type,
        reason: reason,
        penalty-amount: penalty-amount,
        executed-at: current-block,
        executed-by: tx-sender
      })
    (var-set next-enforcement-action-id (+ action-id u1))
    action-id
  )
)

(define-private (log-usage 
  (token-id uint) 
  (user principal) 
  (license-id uint) 
  (action-performed uint) 
  (location (optional (string-ascii 3)))
  (was-authorized bool))
  (let
    (
      (log-id (var-get next-usage-log-id))
      (current-block (get-current-block-height))
    )
    (map-set usage-logs
      { log-id: log-id }
      {
        token-id: token-id,
        user: user,
        license-id: license-id,
        action-performed: action-performed,
        timestamp: current-block,
        location: location,
        ip-hash: none, ;; Could be implemented with additional data
        was-authorized: was-authorized
      })
    (var-set next-usage-log-id (+ log-id u1))
    log-id
  )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - CORE ENFORCEMENT
;; =============================================================================

;; (define-public (enforce-license-terms (token-id uint) (user principal) (action (string-ascii 32)) (license-id uint))
;;   (let
;;     (
;;       (action-type (if (is-eq action "view") ACTION_VIEW
;;                     (if (is-eq action "download") ACTION_DOWNLOAD
;;                     (if (is-eq action "modify") ACTION_MODIFY
;;                     (if (is-eq action "distribute") ACTION_DISTRIBUTE
;;                     (if (is-eq action "commercial") ACTION_COMMERCIAL_USE
;;                     (if (is-eq action "sublicense") ACTION_SUBLICENSE
;;                     u999))))))) ;; Invalid action
;;       (current-block (get-current-block-height))
;;       (user-location (none)) ;; No location provided
;;     )
    
;;     ;; Validate inputs
;;     (asserts! (< action-type u999) ERR_INVALID_ACTION)
;;     (asserts! (is-some (map-get? tokens { token-id: token-id })) ERR_TOKEN_NOT_FOUND)
;;     (asserts! (var-get enforcement-enabled) ERR_UNAUTHORIZED)
    
;;     ;; Check if user is suspended - return early if suspended
;;     (let
;;       (
;;         (compliance-check (match (map-get? user-compliance { user: user })
;;           compliance
;;           (if (get is-suspended compliance)
;;             (if (> current-block (get suspended-until compliance))
;;               ;; Lift suspension and continue
;;               (begin
;;                 (map-set user-compliance
;;                   { user: user }
;;                   (merge compliance { is-suspended: false, suspended-until: u0 }))
;;                 false) ;; Not suspended anymore
;;               ;; Still suspended
;;               true) ;; Still suspended
;;             false) ;; Not suspended
;;           false)) ;; No compliance record - not suspended
;;       )
;;       ;; If user is still suspended, log and return error
;;       (if compliance-check
;;         (begin
;;           (log-usage token-id user license-id action-type user-location false)
;;           (err ERR_USER_SUSPENDED))
;;         ;; User not suspended, continue with validation
;;         (begin
;;           ;; Check license validity
;;           (asserts! (is-license-valid token-id user license-id) ERR_LICENSE_EXPIRED)
          
;;           ;; Check usage limits
;;           (asserts! (check-usage-limits token-id user license-id) ERR_USAGE_LIMIT_EXCEEDED)
          
;;           ;; Check action permissions
;;           (match (map-get? action-permissions { token-id: token-id, license-id: license-id, action-type: action-type })
;;             permission
;;             (begin
;;               (asserts! (get is-permitted permission) ERR_ACTION_NOT_PERMITTED)
              
;;               ;; Check territory restrictions
;;               (if (get territory-restricted permission)
;;                 (if (is-some user-location)
;;                   (let
;;                     (
;;                       (location (unwrap-panic user-location))
;;                       (license (unwrap-panic (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id })))
;;                       (restricted-territories (get territory-restrictions license))
;;                     )
;;                     (asserts! (check-territory-restriction location restricted-territories) ERR_TERRITORY_RESTRICTION)
;;                     true)
;;                   ;; No location provided, skip territory check (could be made stricter)
;;                   true)
;;                 ;; Territory restrictions not enabled
;;                 true)
              
;;               ;; Process payment if required
;;               (if (get requires-payment permission)
;;                 (let
;;                   (
;;                     (payment-amount (get payment-per-use permission))
;;                   )
;;                   ;; In a real implementation, this would handle STX or token transfers
;;                   ;; For now, we'll just check if payment was made (placeholder)
;;                   (asserts! (>= payment-amount u0) ERR_INSUFFICIENT_PAYMENT) ;; Placeholder check
;;                   )
;;                 true)
              
;;               ;; Update usage count
;;               (increment-usage-count token-id user license-id)
              
;;               ;; Log successful usage
;;               (log-usage token-id user license-id action-type user-location true)
              
;;               (print {
;;                 event: "license-terms-enforced",
;;                 token-id: token-id,
;;                 user: user,
;;                 action: action,
;;                 license-id: license-id,
;;                 result: "authorized"
;;               })
              
;;               (ok true))
            
;;             ;; No permission defined - default deny
;;             (begin
;;               (log-usage token-id user license-id action-type user-location false)
;;               (apply-penalty user (var-get default-penalty-rate) u"Attempted unauthorized action")
;;               (log-enforcement-action token-id user action-type "penalty" u"Unauthorized action attempt" (var-get default-penalty-rate))
              
;;               (print {
;;                 event: "license-violation",
;;                 token-id: token-id,
;;                 user: user,
;;                 action: action,
;;                 reason: "no permission defined"
;;               })
              
;;               (err ERR_ACTION_NOT_PERMITTED)))
;;         )) ;; Close the begin and let blocks
;;   ) ;; Close the main let block
;; ) ;; Close the define-public function
;; )

;; =============================================================================
;; PUBLIC FUNCTIONS - LICENSE MANAGEMENT
;; =============================================================================

(define-public (create-license-template
  (license-type uint)
  (name (string-utf8 128))
  (description (string-utf8 512))
  (base-price uint)
  (duration-blocks uint)
  (max-usage-count uint)
  (allowed-actions (list 10 uint))
  (restricted-territories (list 20 (string-ascii 3)))
  (commercial-allowed bool)
  (sublicense-allowed bool)
  (modification-allowed bool)
  (attribution-required bool))
  (let
    (
      (license-id (var-get next-license-template-id))
    )
    ;; Only contract owner or token creators can create templates
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= license-type LICENSE_TYPE_SUBSCRIPTION) ERR_INVALID_LICENSE_TYPE)
    
    (map-set license-templates
      { license-id: license-id }
      {
        license-type: license-type,
        name: name,
        description: description,
        base-price: base-price,
        duration-blocks: duration-blocks,
        max-usage-count: max-usage-count,
        allowed-actions: allowed-actions,
        restricted-territories: restricted-territories,
        commercial-allowed: commercial-allowed,
        sublicense-allowed: sublicense-allowed,
        modification-allowed: modification-allowed,
        attribution-required: attribution-required,
        created-by: tx-sender,
        is-active: true
      })
    
    (var-set next-license-template-id (+ license-id u1))
    
    (print {
      event: "license-template-created",
      license-id: license-id,
      name: name,
      created-by: tx-sender
    })
    
    (ok license-id))
)

(define-public (grant-license 
  (token-id uint) 
  (user principal) 
  (license-id uint) 
  (custom-duration (optional uint))
  (custom-terms (optional (string-utf8 512))))
  (let
    (
      (token (unwrap! (map-get? tokens { token-id: token-id }) ERR_TOKEN_NOT_FOUND))
      (template (unwrap! (map-get? license-templates { license-id: license-id }) ERR_INVALID_LICENSE_TYPE))
      (current-block (get-current-block-height))
      (duration (default-to (get duration-blocks template) custom-duration))
      (expires-at (if (is-eq duration u0) u0 (+ current-block duration)))
    )
    ;; Only token owner can grant licenses
    (asserts! (is-eq tx-sender (get owner token)) ERR_UNAUTHORIZED)
    (asserts! (get is-active template) ERR_INVALID_LICENSE_TYPE)
    
    ;; Create user license
    (map-set user-licenses
      { token-id: token-id, user: user, license-id: license-id }
      {
        granted-at: current-block,
        expires-at: expires-at,
        payment-amount: (get base-price template),
        usage-count: u0,
        max-usage: (get max-usage-count template),
        status: LICENSE_STATUS_ACTIVE,
        territory-restrictions: (get restricted-territories template),
        custom-terms: custom-terms,
        last-used: u0,
        penalty-count: u0
      })
    
    ;; Set up action permissions based on template
    (setup-action-permissions token-id license-id template)
    
    ;; Update token stats
    (map-set tokens
      { token-id: token-id }
      (merge token {
        total-licenses-issued: (+ (get total-licenses-issued token) u1)
      }))
    
    (print {
      event: "license-granted",
      token-id: token-id,
      user: user,
      license-id: license-id,
      expires-at: expires-at
    })
    
    (ok true))
)

(define-private (setup-action-permissions (token-id uint) (license-id uint) (template { license-type: uint, name: (string-utf8 128), description: (string-utf8 512), base-price: uint, duration-blocks: uint, max-usage-count: uint, allowed-actions: (list 10 uint), restricted-territories: (list 20 (string-ascii 3)), commercial-allowed: bool, sublicense-allowed: bool, modification-allowed: bool, attribution-required: bool, created-by: principal, is-active: bool }))
  (let
    (
      (allowed-actions (get allowed-actions template))
    )
    ;; Set permissions for each allowed action
    (map set-single-action-permission
         allowed-actions
         (list token-id token-id token-id token-id token-id token-id token-id token-id token-id token-id)
         (list license-id license-id license-id license-id license-id license-id license-id license-id license-id license-id))
    true)
)

(define-private (set-single-action-permission (action-type uint) (token-id uint) (license-id uint))
  (map-set action-permissions
    { token-id: token-id, license-id: license-id, action-type: action-type }
    {
      is-permitted: true,
      requires-payment: false, ;; Can be customized based on action type
      payment-per-use: u0,
      daily-limit: u0, ;; 0 = unlimited
      territory-restricted: true,
      compliance-required: true
    })
)

;; =============================================================================
;; PUBLIC FUNCTIONS - TOKEN MANAGEMENT
;; =============================================================================

(define-public (register-token 
  (token-id uint)
  (owner principal)
  (title (string-utf8 256))
  (description (string-utf8 512))
  (royalty-percentage uint))
  (begin
    ;; Only contract owner or the token owner can register
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender owner)) ERR_UNAUTHORIZED)
    (asserts! (<= royalty-percentage u10000) ERR_INVALID_ACTION) ;; Max 100%
    
    (map-set tokens
      { token-id: token-id }
      {
        owner: owner,
        creator: tx-sender,
        title: title,
        description: description,
        created-at: (get-current-block-height),
        total-licenses-issued: u0,
        royalty-percentage: royalty-percentage,
        is-active: true
      })
    
    (print {
      event: "token-registered",
      token-id: token-id,
      owner: owner,
      title: title
    })
    
    (ok true))
)

;; =============================================================================
;; PUBLIC FUNCTIONS - ENFORCEMENT ACTIONS
;; =============================================================================

(define-public (revoke-license (token-id uint) (user principal) (license-id uint) (reason (string-utf8 256)))
  (let
    (
      (token (unwrap! (map-get? tokens { token-id: token-id }) ERR_TOKEN_NOT_FOUND))
      (license (unwrap! (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id }) ERR_TOKEN_NOT_FOUND))
    )
    ;; Only token owner can revoke licenses
    (asserts! (is-eq tx-sender (get owner token)) ERR_UNAUTHORIZED)
    
    ;; Update license status
    (map-set user-licenses
      { token-id: token-id, user: user, license-id: license-id }
      (merge license { status: LICENSE_STATUS_REVOKED }))
    
    ;; Log enforcement action
    (log-enforcement-action token-id user u0 "revocation" reason u0)
    
    (print {
      event: "license-revoked",
      token-id: token-id,
      user: user,
      license-id: license-id,
      reason: reason
    })
    
    (ok true))
)

(define-public (suspend-license (token-id uint) (user principal) (license-id uint) (suspension-blocks uint) (reason (string-utf8 256)))
  (let
    (
      (token (unwrap! (map-get? tokens { token-id: token-id }) ERR_TOKEN_NOT_FOUND))
      (license (unwrap! (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id }) ERR_TOKEN_NOT_FOUND))
    )
    ;; Only token owner can suspend licenses
    (asserts! (is-eq tx-sender (get owner token)) ERR_UNAUTHORIZED)
    
    ;; Update license status
    (map-set user-licenses
      { token-id: token-id, user: user, license-id: license-id }
      (merge license { status: LICENSE_STATUS_SUSPENDED }))
    
    ;; Log enforcement action
    (log-enforcement-action token-id user u0 "suspension" reason u0)
    
    (print {
      event: "license-suspended",
      token-id: token-id,
      user: user,
      license-id: license-id,
      suspension-blocks: suspension-blocks,
      reason: reason
    })
    
    (ok true))
)

;; =============================================================================
;; PUBLIC FUNCTIONS - SYSTEM ADMINISTRATION
;; =============================================================================

(define-public (set-enforcement-enabled (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set enforcement-enabled enabled)
    (print { event: "enforcement-status-changed", enabled: enabled })
    (ok true))
)

(define-public (set-default-penalty-rate (rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set default-penalty-rate rate)
    (print { event: "penalty-rate-updated", rate: rate })
    (ok true))
)

(define-public (set-max-violations-before-suspension (max-violations uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set max-violations-before-suspension max-violations)
    (print { event: "max-violations-updated", max-violations: max-violations })
    (ok true))
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-token-info (token-id uint))
  (map-get? tokens { token-id: token-id })
)

(define-read-only (get-license-template (license-id uint))
  (map-get? license-templates { license-id: license-id })
)

(define-read-only (get-user-license (token-id uint) (user principal) (license-id uint))
  (map-get? user-licenses { token-id: token-id, user: user, license-id: license-id })
)

(define-read-only (get-action-permission (token-id uint) (license-id uint) (action-type uint))
  (map-get? action-permissions { token-id: token-id, license-id: license-id, action-type: action-type })
)

(define-read-only (get-user-compliance (user principal))
  (map-get? user-compliance { user: user })
)

(define-read-only (get-enforcement-action (action-id uint))
  (map-get? enforcement-actions { action-id: action-id })
)

(define-read-only (get-usage-log (log-id uint))
  (map-get? usage-logs { log-id: log-id })
)

(define-read-only (is-user-authorized (token-id uint) (user principal) (license-id uint) (action-type uint))
  (and
    (is-license-valid token-id user license-id)
    (check-usage-limits token-id user license-id)
    (match (map-get? user-compliance { user: user })
      compliance (not (get is-suspended compliance))
      true)
    (match (map-get? action-permissions { token-id: token-id, license-id: license-id, action-type: action-type })
      permission (get is-permitted permission)
      false))
)

(define-read-only (get-enforcement-settings)
  {
    enforcement-enabled: (var-get enforcement-enabled),
    default-penalty-rate: (var-get default-penalty-rate),
    max-violations-before-suspension: (var-get max-violations-before-suspension),
    suspension-duration-blocks: (var-get suspension-duration-blocks)
  }
)