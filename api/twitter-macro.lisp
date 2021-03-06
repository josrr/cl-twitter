(in-package :twitter)

(defmacro fixup (lst)
  `(and (keywordp (car ,lst)) (cons nil ,lst))) 

(defmacro with-gensyms ((&rest names) &rest body)
  `(let ,(loop for n in names collect `(,n (gensym)))
     ,@body))


(defun push-until-keyword (lst &optional (accum nil))
  (cond ((keywordp (car lst)) (values accum lst))
	((null lst)           (values accum lst))
	(t                    (push-until-keyword (cdr lst) (cons (car lst) accum)))))

(defun strip-keyword-2 (keyword plist)
  (multiple-value-bind (head rest) (push-until-keyword plist)
    (nconc head (strip-keyword keyword rest))))

;; Original 2016-07-21 José Miguel Ronquillo Rivera
;; max -> max calls not max results
(defmacro with-cursor% ((&key (max -1) (collector #'identity) (skip 0) (extractor nil) (controller (lambda (x) (declare (ignore x)) 0))  (test (lambda() nil) ) (cursor :cursor))  &rest body)
  (with-gensyms ($max $skip fn targs kargs _cursor_ cursor-id fn_ args_ args nocursor_args nocursor_kargs)
    `(macrolet ((unpack$ ( (,fn_ &rest ,args_) )
		  `(values (quote ,,fn_) (list ,@,args_))))
       (multiple-value-bind (,fn ,targs) (unpack$ ,@body)
	 (multiple-value-bind (,args ,kargs) (split-to-key ,targs)
	   (let ((,$max (+ 1 ,max ,skip))
		 (,$skip ,skip)
		 (,_cursor_ (or (cadr (member ,cursor ,kargs)) -1))
		 (,nocursor_kargs (strip-keyword-2 ,cursor ,kargs))
		 (,nocursor_args (strip-keyword-2 ,cursor ,args)))
	     (do () ((or (zerop ,_cursor_) (zerop (decf ,$max)) (funcall ,test)))
	       (progn
		 ;;#+nil(format t "**[~A;~A] ~A ~S~%" ,nocursor_kargs ,nocursor_args ,fn (append ,nocursor_args ,nocursor_kargs (list ,cursor ,_cursor_)))
		 (let ((,cursor-id (apply ,fn (append ,nocursor_args ,nocursor_kargs (list ,cursor ,_cursor_)))))
		   (if (zerop ,$skip)
		       (funcall ,collector (funcall ,extractor ,cursor-id))
		       (decf ,$skip))
		   (setf ,_cursor_ (funcall ,controller ,cursor-id)))))))))))

(defmacro with-cursor ((&key (max -1) (collector #'identity)
			     (skip 0) (extractor nil)
			     (controller (lambda (x) (declare (ignore x)) 0))
			     (test (lambda() nil) )
			     (cursor :cursor))  &rest body)
  (with-gensyms ($max $skip fn targs kargs _cursor_ cursor-id fn_ args_ args nocursor_args nocursor_kargs)
    `(macrolet ((unpack$ ( (,fn_ &rest ,args_) )
		  `(values (quote ,,fn_) (list ,@,args_))))
       (multiple-value-bind (,fn ,targs) (unpack$ ,@body)
	 ;;(format t "~S ~S~%" ,fn ,targs)
	 (multiple-value-bind (,args ,kargs) (split-to-key ,targs)
	   ;;(format t "~S ~S~%" ,args ,kargs)
	   (let ((,$max (+ 1 ,max ,skip))
		 (,$skip ,skip)
		 (,_cursor_ (or (cadr (member ,cursor ,kargs)) nil))
		 (,nocursor_kargs (strip-keyword-2 ,cursor ,kargs))
		 (,nocursor_args (strip-keyword-2 ,cursor ,args)))
	     (do () ((or (and ,_cursor_ (zerop ,_cursor_))
			 (zerop (decf ,$max)) (funcall ,test)))
	       #+nil
	       (format t "**[~A;~A] ~A ~S~%" ,nocursor_kargs ,nocursor_args ,fn (append ,nocursor_args ,nocursor_kargs (list ,cursor ,_cursor_)))
	       (let ((,cursor-id (apply ,fn (append ,nocursor_args ,nocursor_kargs
						    (when ,_cursor_ (list ,cursor ,_cursor_))))))
		 ;;(format t "cursor-id: ~S skip: ~S~%" ,cursor-id ,$skip)
		 (if (zerop ,$skip)
		     (progn
		       ;;(log:debug "if ~S~%" ,cursor-id)
		       (funcall ,collector (funcall ,extractor ,cursor-id)))
		     (decf ,$skip))
		 ;;(format t "cursor-id: ~S~%" ,cursor-id)
		 (setf ,_cursor_ (funcall ,controller ,cursor-id))))))))))

;; Original 2016-07-21 José Miguel Ronquillo Rivera
;; La mayoría de end-points del API 1.1 de Twitter ya no usan page, sino max-id para
;; paginar los resultados
(defmacro collect-tweets% ((&key (max 1) (skip 0) (container (make-hash-table  :test 'equal :size 100))) &rest body)
  (with-gensyms (ht ht-size page lst item)
    `(let ((,ht-size 0)
	   (,ht nil)
	   (,page 1))
       (labels ((collect-it (,lst)
		  (dolist (,item ,lst)
		    (setf (gethash (tweet-id ,item) ,ht) ,item)))
		(stop-it ()
		  (prog1
		      (or (rate-limit-exceeded) (and (< 0 ,ht-size) (= ,ht-size (hash-table-count ,ht))))
		    (setf ,ht-size (hash-table-count ,ht))))
		(next-page (,item)
		  (declare (ignore ,item))
		  (decf ,page)))
	 (setf ,ht ,container)
	 (with-cursor (:skip ,skip :max ,max :extractor #'identity :controller #'next-page :collector #'collect-it :test #'stop-it :cursor :page) (,@body :page ,page)))
       ,ht)))


(defun statuses-rate-limit-exceeded (&optional (type :home-timeline))
  ;;(log:debug type)
  (let ((rates (cdr (assoc :remaining
			   (cdr (assoc (intern (concatenate 'string "/STATUSES/"
							    (symbol-name type)) :keyword)
				       (cdr (assoc :statuses
						   (rate-limit-resources
						    (rate-limit-status :resources "statuses"))))))))))
    (values (zerop rates) rates)))

(defmacro collect-tweets ((&key (type :home-timeline)
				(count 15)
				(max 1) (skip 0) (container (make-hash-table :test 'equal :size 100))) &rest body)
  (with-gensyms (ht ht-size max-id lst item)
    `(let ((,ht-size 0)
	   (,ht nil)
	   (,max-id nil))
       (labels ((collect-it (,lst)
		  ;;(log:debug "lst:~%~S~%" ,lst)
		  (dolist (,item ,lst)
		    (setf (gethash (tweet-id ,item) ,ht) ,item)))
		(stop-it ()
		  ;;(log:debug "stop-it~%")
		  (prog1
		      (or (statuses-rate-limit-exceeded ,type) (and (< 0 ,ht-size) (= ,ht-size (hash-table-count ,ht))))
		    (setf ,ht-size (hash-table-count ,ht))))
		(next-page (,item)
		  ;;(declare (ignore ,item))
		  ;;(log:debug "next-page item:~%~S~%" ,item)
		  (when ,item
		    (setf ,max-id (1- (reduce #'min (mapcar #'tweet-id ,item)))))))
	 (setf ,ht ,container)
	 ;;(log:debug "antes de with-cursor~%")
	 (with-cursor (:skip ,skip :max ,max :extractor #'identity :controller #'next-page :collector #'collect-it :test #'stop-it :cursor :max-id) (,@body :max-id ,max-id :count ,count)))
       ,ht)))


;; Original 2016-07-20 José Miguel Ronquillo Rivera
(defmacro with-paging% ((&key (max 1500) (max-pages 15) (collector #'identity) (skip 0) (controller nil) (test (lambda() nil)) )  &rest body)
  (with-gensyms ($results $max $skip fn kargs _page_ args twitter-search fn_ args_ $rpp)
    `(macrolet ((unpack$ ( (,fn_ &rest ,args_) )
		  `(values (quote ,,fn_) (list ,@,args_))))
       (multiple-value-bind (,fn ,kargs) (unpack$ ,@body)
	 (destructuring-bind (,args &key callback lang locale rpp page since-id until geocode show-user result-type) ,kargs
	   (let ((,$max ,max)
		 (,$skip ,skip)
		 (,$results 0)
		 (,$rpp (or rpp 100))
		 (,_page_ (or page 1)))
	     (do () ((or (> ,_page_ ,max-pages) (> 0 (- ,$max ,$results)) (funcall ,test) ))
	       (progn
		 (let ((,twitter-search (funcall ,fn ,args :page ,_page_ :rpp ,$rpp :lang lang
						 :callback callback :locale locale :since-id since-id
						 :until until :geocode geocode :show-user show-user
						 :result-type result-type)))
		   (incf ,$results (length (search-result-results ,twitter-search)))
		   (if (zerop ,$skip)
		       (funcall ,collector (search-results ,twitter-search))
		       (decf ,$skip ,$results ))
		   (if (null ,controller)
		       (incf ,_page_)
		       (setf ,_page_ (funcall ,controller ,twitter-search))))))))))))

;; 1. La búsqueda de la versión 1.1 del API de twitter no soporta el parámetro 'page'
(defmacro with-paging ((&key (max 1500) (max-pages 15) (collector #'identity) (skip 0) (controller nil) (test (lambda() nil)) )  &rest body)
  (with-gensyms ($results $max $skip fn kargs _page_ args twitter-search fn_ args_ $rpp)
    `(macrolet ((unpack$ ( (,fn_ &rest ,args_) )
		  `(values (quote ,,fn_) (list ,@,args_))))
       (multiple-value-bind (,fn ,kargs) (unpack$ ,@body)
	 (destructuring-bind (,args &key callback lang locale rpp page since-id until geocode show-user result-type) ,kargs
	   (let ((,$max ,max)
		 (,$skip ,skip)
		 (,$results 0)
		 (,$rpp (or rpp 100))
		 (,_page_ (or page 1)))
	     (do () ((or (> ,_page_ ,max-pages) (> 0 (- ,$max ,$results)) (funcall ,test) ))
	       (progn
		 (let ((,twitter-search (funcall ,fn ,args ;; :page ,_page_ :rpp ,$rpp ;; 1
						 :lang lang
						 :callback callback :locale locale :since-id since-id
						 :until until :geocode geocode :show-user show-user
						 :result-type result-type)))
		   (incf ,$results (length (search-results ,twitter-search)))
		   (if (zerop ,$skip)
		       (funcall ,collector (search-results ,twitter-search))
		       (decf ,$skip ,$results ))
		   (if (null ,controller)
		       (incf ,_page_)
		       (setf ,_page_ (funcall ,controller ,twitter-search))))))))))))

;;
;; Doesn't work when you have more than one argument. I would need to take the car of the twitter-command list and the cdr would
;; have to be zipped with the arg-list... TBD for now
;;
;;(defmacro define-twitter-method (method (arg-list &rest keys) &body twitter-command)
;;  (labels ((construct-arg-list (lst &optional (accum nil))
;;	     (labels ((add-pair (l r lst)
;;			(cons l (cons r lst))))
;;	       (cond ( (null lst) accum)
;;		     ( (atom (car lst)) (construct-arg-list (cdr lst) (add-pair (intern (symbol-name (car lst)) :keyword) (car lst) accum)))
;;		     ( t          (construct-arg-list (cdr lst) (add-pair (intern (symbol-name (car (car lst))) :keyword) (car (car lst)) accum)))))))
;;    (let ((cmd-sym (intern (symbol-name method)))
;;	  (key-list (construct-arg-list (cdr keys) )))
;;     `(defun ,cmd-sym (,@arg-list ,@keys)
;;	 (apply 'twitter-op ,@twitter-command ,@arg-list (list ,@key-list))))))

