;;; Copyright (c) 2012, Lorenz Moesenlechner <moesenle@in.tum.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors 
;;;       may be used to endorse or promote products derived from this software 
;;;       without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :pr2-manipulation-knowledge)

(defun calculate-put-down-hand-pose (object-designator put-down-pose)
  (let ((current-object (desig:current-desig object-designator)))
    (desig:with-desig-props (desig-props:at) current-object
      (assert desig-props:at () "Object ~a needs to have an `at' property"
              current-object)
      (desig:with-desig-props (in pose z-offset) at
        (assert (eq in 'gripper) ()
                "Object ~a needs to be in the gripper" current-object)
        (assert pose () "Object ~a needs to have a `pose' property" current-object)
        (assert z-offset () "Object ~a needs to have a `height' property" current-object)
        (cl-transforms:transform->pose
         (cl-transforms:transform*
          (cl-transforms:pose->transform put-down-pose)
          (cl-transforms:make-transform
           (cl-transforms:make-3d-vector 0 0 desig-props:z-offset)
           (cl-transforms:make-identity-rotation))
          (cl-transforms:transform-inv
           (cl-transforms:pose->transform desig-props:pose))))))))

(def-fact-group pick-and-place-manipulation (trajectory-point)

  (<- (trajectory-point ?designator ?point ?side)
    (trajectory-desig? ?designator)
    (desig-prop ?designator (to grasp))
    (desig-prop ?designator (obj ?obj))
    (desig-prop ?designator (side ?side))
    (desig-location-prop ?obj ?pose)
    (lisp-fun cl-transforms:origin ?pose ?point))

  (<- (trajectory-point ?designator ?point ?side)
    (trajectory-desig? ?designator)
    (desig-prop ?designator (to put-down))
    (desig-prop ?designator (obj ?object))
    (desig-prop ?designator (side ?side))
    (desig-prop ?designator (at ?location))
    (lisp-fun current-desig ?location ?current-location)
    (lisp-fun reference ?current-location ?put-down-pose)
    (lisp-fun calculate-put-down-hand-pose ?object ?put-down-pose ?point)))