(cl:in-package #:concrete-syntax-tree)

(defgeneric completer-action (symbol origin state))

;; (defmethod completer-action (symbol origin state)
;;   (declare (ignore symbol state origin))
;;   nil)

(defmethod completer-action
    ((symbol grammar-symbol) (origin earley-state) (state earley-state))
  (loop for item in (items origin)
        when (subtypep symbol (left-hand-side item))
          do (let ((new (make-instance 'earley-item
                          :rule (rule item)
                          :dot-position (1+ (dot-position item))
                          :origin (origin item)
                          :parse-trees (cl:cons symbol (parse-trees item)))))
               (possibly-add-item new state))))

(defgeneric predictor-action (symbol grammar state))

(defmethod predictor-action
    ((symbol grammar-symbol) (grammar grammar) (state earley-state))
  (loop for rule in (rules grammar)
        when (subtypep (left-hand-side rule) symbol)
          do (let ((new (make-instance 'earley-item
                          :rule rule
                          :dot-position 0
                          :origin state
                          :parse-trees '())))
               (possibly-add-item new state))))

(defclass parser ()
  ((%client :initarg :client :reader client)
   (%lambda-list :initarg :lambda-list :reader lambda-list)
   (%grammar :initarg :grammar :reader grammar)
   (%all-states :initarg :states :reader all-states)
   (%all-input :initarg :input :reader all-input)
   (%remaining-states :initarg :states :accessor remaining-states)
   (%remaining-input :initarg :input :accessor remaining-input)))

(defmethod initialize-instance :after ((object parser) &key rules)
  (let* ((states (loop repeat (1+ (length (all-input object)))
                       collect (make-instance 'earley-state)))
         (grammar (make-instance 'grammar :rules rules))
         (target-rule (find 'target (rules grammar) :key #'left-hand-side))
         (item (make-instance 'earley-item
                 :parse-trees '()
                 :origin (car states)
                 :dot-position 0
                 :rule target-rule)))
    (push item (car states))
    (reinitialize-instance
     object
     :states states
     :grammar grammar)))

(defgeneric process-current-state (parser))

(defmethod process-current-state ((parser parser))
  (let ((states (remaining-states parser))
        (client (client parser))
        (lambda-list (lambda-list parser))
        (remaining-input (remaining-input parser)))
    (loop with state = (car states)
          for remaining-items = (items state) then (cdr remaining-items)
          until (cl:null remaining-items)
          do (let* ((item (car remaining-items))
                    (pos (dot-position item))
                    (rule (rule item))
                    (lhs (left-hand-side rule))
                    (rhs (right-hand-side rule)))
               (if (= pos (length rhs))
                   (let* ((lhs-class (find-class lhs))
                          (proto (make-instance lhs-class)))
                     (completer-action proto (origin item) state))
                   (let* ((terminal (cl:nth pos rhs))
                          (terminal-class (find-class terminal))
                          (proto (make-instance terminal-class))
                          (scan-result
                            (if (cl:null remaining-input)
                                nil
                                (scanner-action client
                                                item
                                                lambda-list
                                                proto
                                                (car remaining-input)))))
                     (unless (cl:null scan-result)
                       (let ((next-state (cadr states)))
                         (possibly-add-item scan-result next-state)))))))))

(defgeneric parse-step (parser))

(defmethod parse-step ((parser parser))
  (process-current-state parser)
  (cl:pop (remaining-input parser))
  (cl:pop (remaining-states parser)))

(defgeneric parse (parser))

(defmethod parse ((parser parser))
  (loop do (parse-step parser)
        until (null (remaining-input parser))))