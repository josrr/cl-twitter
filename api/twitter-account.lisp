(in-package :twitter)

;;((:RESET-TIME . "Mon Nov 22 02:33:43 +0000 2010")
;; (:RESET-TIME-IN-SECONDS . 1290393223) (:REMAINING-HITS . 350)
;; (:HOURLY-LIMIT . 350))

(define-element rate-limit ()
  "rate limit type"
  (resources "" nil)
  (id         "" nil)
  (reset-time "" nil)
  (reset-time-in-seconds "" nil)
  (remaining-hits "" nil)
  (hourly-limit   "" nil))


(defmethod print-object ((ref rate-limit) stream)
  (format stream "#<TWITTER-RATE-LIMIT '~A:~A'>" (rate-limit-remaining-hits ref) (rate-limit-hourly-limit ref)))


(defun print-rate-limit (ref)
  (format t "~A: ~A~%" (rate-limit-remaining-hits ref) (rate-limit-hourly-limit ref)))

(defun rate-limit-exceeded ()
  (let ((rls (rate-limit-status :resources "application")))
    (let ((rates (cdr (assoc :remaining
			     (cdr (assoc ::/APPLICATION/RATE-LIMIT-STATUS
					 (cdr (assoc :application
						     (twitter::rate-limit-resources rls)))))))))
      (values (zerop rates) rates))))

;; end session element
;;((:REQUEST . "/1/account/end_session.json") (:ERROR . "Logged out."))

(define-element end-session ()
    "rate limit type"
  (id         "" nil)
  (request "" nil)
  (error "" nil))

(defmethod print-object ((ref end-session) stream)
  (format stream "#<TWITTER-END-SESSION '~A:~A'>" (end-session-request ref) (end-session-error ref)))

(defun print-end-session (ref)
  (format t "~A: ~A~%" (end-session-request ref) (end-session-error ref)))

;;
;; ACCOUNT METHODS
;;
;; Unsupported calls are marked with an X
;;
;;   Account resources
;;        account/verify_credentials
;;        account/rate_limit_status
;;        account/end_session
;;        account/update_delivery_device X
;;        account/update_profile_colors
;;        account/update_profile_image X
;;        account/update_profile_background_image X
;;        account/update_profile
;;


(define-command account/verify-credentials (:get :twitter-user)
    (twitter-app-uri "account/verify_credentials.json")
    :include_entities "When set to either true, t or 1, each tweet will include a node called entities")

;;Calls to rate_limit_status do not count against the rate limit.  
;;If authentication credentials are provided, the rate limit status for the authenticating user is returned.  
;;Otherwise, the rate limit status for the requester's IP address is returned.")

(define-command application/rate-limit-status (:get :rate-limit)
    (twitter-app-uri "application/rate_limit_status.json")
    "Returns the remaining number of API requests available to the requesting user before the API limit is reached for the current hour. ")

(define-command account/end-session (:post :end-session)
    (twitter-app-uri "account/end_session.json")
    "Ends the session of the authenticating user, returning a null cookie.")

;;TODO : doesn't work; parsing error
(define-command account/update-delivery-device (:post :identity)
    (twitter-app-uri "account/update_delivery_device.json")
    "Sets which device Twitter delivers updates to for the authenticating user.  Sending none as the device parameter will disable IM or SMS updates."
  :device "Required.  Must be one of: sms, im, none.")

 
(define-command account/update-profile-colors (:post :twitter-user)
    (twitter-app-uri "account/update_profile_colors.json")
    "Sets one or more hex values that control the color scheme of the authenticating user's
     profile page on twitter.com.  These values are also returned in the /users/show 
     API method."
  :profile-background-color "Optional. "
  :profile-text-color "Optional"
  :profile-link-color "Optional"
  :profile-sidebar-fill-color "Optional"
  :profile-sidebar-border-color "Optional"
  :include_entities "When set to either true, t or 1, each tweet will include a node called entities")

;; not tested 
(define-command account/update-profile-image (:post :twitter-user)
    (twitter-app-uri "account/update_profile_image.json")
    "Updates the authenticating user's profile image.  Expects raw multipart data, not a URL to an image."
  :image "Required.  Must be a valid GIF, JPG, or PNG image of less than 700 kilobytes in size.  Images with width larger than 500 pixels will be scaled down."
  :include_entities "When set to either true, t or 1, each tweet will include a node called entities")


;;not tested
(define-command account/update-profile-background-image (:post :twitter-user)
    (twitter-app-uri "account/update_profile_background_image.json")
    "Updates the authenticating user's profile background image.  Expects raw multipart data, not a URL to an image."
  :image "Required.  Must be a valid GIF, JPG, or PNG image of less than 800 kilobytes in size.  Images with width larger than 2048 pixels will be scaled down."
  :tile "Whether or not to tile the background image. If set to true the background image will be displayed tiled. The image will not be tiled otherwise."
  :include_entities "When set to either true, t or 1, each tweet will include a node called entities")


;;Only the parameters specified will be updated; to only update the 'name' attribute, for example, only include that parameter in your request."
(define-command account/update-profile (:post :twitter-user)
    (twitter-app-uri "account/update_profile.json")
    "Sets values that users are able to set under the 'Account' tab of their settings page."
  :name             "Optional. Maximum of 20 characters. One or more of all these parameters must be present."
  :url              "Optional. Maximum of 100 characters. Will be prepended with 'http://' if not present."
  :location         "Optional. Maximum of 30 characters. The contents are not normalized or geocoded in any way."
  :description      "Optional. Maximum of 160 characters."
  :include_entities "When set to either true, t or 1, each tweet will include a node called entities")

(define-command account/settings (:get :twitter-user)
    (twitter-app-uri "account/settings.json")
    "Gets the settings values.")

;;----------------------- end of account methods -----------------------------------------------------------------------------

(define-twitter-method verify-credentials (() &key (include-entities t)) :account/verify-credentials)
(define-twitter-method rate-limit-status  (() &key (resources nil))     :application/rate-limit-status)
(define-twitter-method end-session        (())                           :account/end-session)


(define-twitter-method settings (()) :account/settings )

(define-twitter-method update-profile-colors (() &key (profile-background-color nil)  (profile-text-color nil)  (profile-link-color nil)  
			      (profile-sidebar-fill-color nil)  (profile-sidebar-border-color nil)  (include_entities t))     :account-update-profile-colors )

(define-twitter-method update-profile (() &key (name nil)  (url nil) (location nil) (description nil) (include_entities t)) :account-update-profile)
