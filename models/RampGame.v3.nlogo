; RampGame
; Sept 16, 2013
; Started July 22, 2013
; Based on SuperRamp
; Bob Tinker
; Copyright, the Concord Consortium

; This version is set up to log data

__includes [ "data-export-modular.nls" ]

globals [
  focus old-focus                ; focus contains the number of the current window
  old-mouse-down? 
  helper-who                     ; the who of the help button
  messages-shown                 ; counts the number of messages shown at each level
  output-width
  ; define the windows. Each of the following is a LIST
  u-wind-lt u-wind-rt v-wind-bot v-wind-top  
  mx bx my by       ; LISTS of transformation coefs
  ul ur vb vt       ; the window boundaries of the focus window

  mxx bxx myy byy   ; the transformation coef for the focus window
  n-wind            ; the number of windows
  starting? 
  running?          ; true when the car is running
  old-x-center
  old-y-center
  old-magnification
  old-vehicle-loc
  old-running?
  ramp max-y-ramp min-y-ramp
  selected-ramp-index
  ramp-color
  mass
  vehicle-colors
  vehicle-shapes
  vehicle-masses
  vehicle-starts
  vehicle-offsets
  vehicle-sizes
  move-ramp-left?   ; set true when the vehicle runs off one side or the other
  move-ramp-right?
  v-who          ; a list of the whos of visible vehicles
  selected-vehicle    ; the who of the vehicle the user clicked on--accurate only if click=2
  blinking?         ; tells whether vehicle selected-vehicle should blink
                 ; when blinking, the selected vehicle's parameters can be set in the graphing area. 
  old-blinking?     ; used to detect a change in blinking status to insure that the old blinking vehicle is left on
  magnification 
  y-axis
  g        ; acceleration of gravity 9.81 m/s^2
  time     ; the model time
  dt       ; the time step
  height dist
  saved-time-series ; a list of lists containing [t, x, y, speed] for every .5 sec
  start-height  ;
  data-series
  saved-starting-x
  data-saved?
  
  snap               ; used in snap to zero--the radius that causes the snap
  click              ; indicates the response required after a mouse click. 
                     ; zero means none, 1 means a ramp handle
                     ; two means the vehicle, 3 means drag the ramp
  u-click v-click    ; the u,v coordinates of the background where the mouse clicked
  x-center y-center  ; the location of the center of the window 1 screen in x,y coordinates
  old-y-axis
  run-number
  Dist-from-zero
  
  grid-umax grid-umin  ; the boundaries of the graphing grid in window 2
  grid-vmax grid-vmin
  edge edge+  ; the distance between the window and the grid in screen units 
  grid-xmin grid-xmax grid-xlabel
  grid-ymin grid-ymax grid-ylabel
  grid-color grid-label-color
  grid-separation       ; target number of pixels per grid line
  tic-length            ; number of pixels the tic extends beyond the axis
  line-width            ; width of lines in the grid.
  
  total-score           ; score since the beginning
  score-last-run        ; score earned in the last run
  level                 ; the current level
  step                  ; the current step in the current level
  loops-at-zero  ; the number of times go is called when speed is zero before the program stops
  countdown ; used to record the times waited, starting at loops-at-zero
  
  ; game variables
  instructions            ; text 
  number-of-hints
  friction-locked?
  air-friction-locked?
  starting-position-locked?
  ramp-locked? 
  old-air-friction
  old-friction
  old-starting-position
  starting-position-min ; the smallest starting position allowed (a negative value)
  starting-position-max
  max-score             ; the maximum score a user could earn for the current level
  n-steps               ; the number of steps in the current level
  target                ; the target location for the current step and level
  target-radius-max     ; the maximum radius at this step, corresponding to step 1
  target-radius-min     ; the minimum radius at this step, correspondind to step n-steps
  target-radius         ; the radius for this level and step
  target-max            ; the maximum position of the target 
  target-min            ; the minimum position of the target
  max-level   ; the number of levels in the game
  marker-1              ; the who of the left-hand marker of the target range
  marker-2              ; the who of the right-hand marker
  waiting-for-setup?   ; used to force the user to press setup before running. 
  final-position        ; the final position of the car at the end of a run

]

breed [drawing-dots drawing-dot]      ; used for the track
breed [grid-dots grid-dot]            ; used for drawing the graphing grid. 
breed [graph-dots graph-dot]          ; used for graphs
breed [vehicles vehicle]
breed [buttons button]
breed [readers reader]                ; used for read-out at the cursor
breed [markers marker]                ; used to show the target
breed [helpers helper]                ; used to implement the help button

vehicles-own [x-val y-val speed frict my-mass offset size-100 spring-left? spring-right?]       ; x-val y-val are the x,y locations. 
graph-dots-own [run-num x-val y-val speed momentum Potential Kinetic]                     ; these store everything that they need for any graph type
buttons-own [default-shape pressed-shape command pressed? short-name long-name]   ; soft buttons. When pressed, the command is executed. 
markers-own [x-val y-val]       ; these markers might be off-screen, so their physical space location is stored in x-val y-val
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;; End of preliminaries ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to startup  ; structured this way in order to have a start page
  ca        ; I use the start page for a reminder to turn on the "go" button
  reset-ticks
  draw-first-page
  set starting? true
end

to go              ; this is the main forever button
  if starting? [
    ask drawing-dots [die]  ;gets rid of the startup message
    initialize
    set starting? false
    reset-timer]
  if running? [
    run-vehicles  ; computes the motion of the vehicles
    every .02 [update-displays]]
  if not running? and old-running? [capture-final-state]  ; used to save final data for export
  every .1 [   ; do the following every tenth second
    act-on-changes
    support-mouse]   ; maintains the action step, sets parameters, handles the screen, shows score, etc 
  tick
end

to update-displays
  ; also updates the exported time-series
  if running? [  ; draw a dot on the graph for the vehicle
    let w first v-who ; v-who is a relic of a multi-vehicle version of this program
    let c [color] of vehicle w ; color of this vehicle
    set dist-from-zero precision ([x-val] of vehicle w )  2 ; the location of this vehicle
    set height precision ([y-val] of vehicle w) 2
    place-point time dist-from-zero c 
    let s precision ([speed] of vehicle w) 2
    set data-series lput (list time dist-from-zero height s ) data-series ]
end

to-report uv-of-vehicle ; in vehicle context, reports the screen coordinates [u v] of that vehicle
  ; also sets the heading of the vehicle and its y-val
  switch-focus-to 1  
  let disp offset * .01 * magnification
  let u mxx * x-val + bxx
  let info vehicle-info ramp x-val
  let y first info 
  set y-val y
  set height y
  let v myy * y + byy
  set heading (last info) - 90
  set disp disp / cos heading
  report list u (v + disp)
end

to place-vehicle [x]  ; in vehicle contexts, puts the vehicle on the track 
  set size size-100 * .01 * magnification
  set x-val x     ; update the vehicle variable x-val
  set dist-from-zero x
  let loc uv-of-vehicle       ; get the [u v] coordinates of the vehicle 
  let u first loc let v last loc
  ifelse in-wind? u v
    [st setxy u v]
    [ht]
end

to act-on-changes
  if magnification != old-magnification [ 
    move-ramp 
    set old-magnification magnification ]
  if y-axis != old-y-axis [
    update-y-axis 
    draw-grid
    set old-y-axis y-axis ]
  if move-ramp-left? or move-ramp-right? [move-ramp]
  
  if friction != old-friction [          ; if the user tries to change the friction...
    ifelse friction-locked? or running?      ;   and the friction slider is supposed to be locked or the model is running
      [ wait .6 set friction old-friction 
        user-message "The friction is locked at this level. You cannot change it now."
        set friction old-friction  ]       ;   then reset the slider to its old position
      [set old-friction friction]]       ; otherwise allow the change

end

to draw-first-page
  ask patches [set pcolor grey + 2]
  create-drawing-dots 1 [
    set size .1
    setxy .4 * min-pxcor .9 * max-pycor
    set label   "Press the On/Off button to continue." ]
  create-drawing-dots 1 [
    set size .1
    setxy .5 * min-pxcor .85 * max-pycor
    set label "   Leave it on all the time." ]
  ask drawing-dots [set label-color red]
end

to initialize
  set magnification 100
  set n-wind 3    ; three windows
  set old-focus 0 ; zero stands for no focus
  set old-mouse-down? false
  set snap .05
  set magnification 100
  set old-magnification magnification
  set g 9.81 ; acceleration of gravity
  set dt .00004 ; the time step
  set x-center 1.35 set y-center .5
  set running? false
  set blinking? false
  set old-blinking? false
  set run-number -1
  set mx [0 0 0] set my mx ; initialize these three as list of three
  set bx mx set by my      ; they will be used to hold the transformation coefs    
  define-windows
  define-transforms  ; actually only creates transforms for window 1
                     ; draw-grid calculates the transformations for window 2 
                     ; and places them in mx, bx, my, by
  ; now set the default grid values and draw the grid in window 2
  set-boundaries-for 2 set focus 2  ; the graphing window
  set edge 10 set edge+ 25  
  set grid-umin ul + 1.8 * edge+ 
  set grid-umax ur - edge
  set grid-vmin vb + edge+
  set grid-vmax vt - 1.5 * edge
  set grid-separation 30    ; the approximate number of pixels per grid line
  set grid-xmin 0   set grid-xmax 4 set grid-xlabel "Time (s)"
  set grid-ymin -2 set grid-ymax 5  set grid-ylabel "Distance (m)"
  set y-axis grid-ylabel  ; this is the pull-down in the UI
  set grid-color blue + 3 set grid-label-color blue - 1
  set tic-length 5   ; the distance a tic mark extends beyond the axis
  set line-width 1    ; the thin lines that make up the grid
  draw-grid  ; creates the grid. It will change graph-xmin etc and the transformation coefs for the focus window 
 
  switch-focus-to 1
  create-help-button

  set ramp-color blue + 2
  set ramp [[-1.3 1][0 0][1 0][2 0][3 0][4 0][5 0][8 0]] ; the initial ramp

  set move-ramp-left? false
  set move-ramp-right? false
  move-ramp ; draws ramp
  set selected-ramp-index false ; this is the index of the pair in ramp that the mouse has selected and drags
  ; define six possible vehicles
  set vehicle-colors (list cyan green 44 blue magenta orange)
  set vehicle-shapes [ "car" "truck" "bus" "engine" "ball" "ambulance"] 
  set vehicle-masses [ .1 .5 .5 2 .02 .3]
  set vehicle-starts [ -1 1.5 2 3 4 -.5]
  set vehicle-offsets [9 8 10 13 6 9  ]  ; distance the turtle center is above the ramp for magnification of 100
  set vehicle-sizes [20 28 33 30 10 30 ]    ; the size of the turtle for magnification of 100
  set saved-starting-x -1
  set v-who []  ; initialize to zero vehicles, then add one
  add-vehicle
  create-readers 1 [ht set label-color black
    set size .1 set shape "dot" ]  ; used for read-out at the cursor in window 2
  ; markers mark the target. They are two arrowheads linked by a thick line
  create-markers 1 [ht set marker-1 who set color red set size .1 set heading 0]
  create-markers 1 [ht set marker-2 who set color red set size .1 set heading 0
    create-link-with marker marker-1 [
      set thickness 6 set color red]]
  set data-saved? true
  set output-width  48      ; characters in the output box, used with pretty-print
  setup-new-run
  set total-score 0
  set score-last-run 0
  set messages-shown [0 0 0 0 0 0 ] ; initializes the number of help messages already shown to the student, by level

  set loops-at-zero 10000
  set countdown loops-at-zero
  set level 1       ;start at level 1
  set step 1        ; start at step 1
  set max-level 4   ; the number of levels in the game. Used to stop advancing beyond this level
  setup-game        ; setup for level 1 step 1
  show-target
  clear-output
  pretty-print "Make the car stop in the middle of the red zone. You can adjust the starting position of the car."
  setup-data-export    ;;; used to define the structure of the exported data
  tick

end

to create-help-button
  ask helpers [die]
  create-helpers 1 [      ; draw the button
    set helper-who who
    set shape "button" set color lime
    setxy max-pxcor - 40 max-pycor - 25
    set heading 0
    set size 75 ]
  create-helpers 1 [ 
    set shape "dot" 
    set color lime set size 1
    setxy max-pxcor - 26 max-pycor - 26
    set label "HINT" set label-color black
    set heading 0 ]
end

to-report on-button
  report mouse-xcor > max-pxcor - 72 and
         mouse-ycor > max-pycor - 45
end
    

to-report in-grid? [u v] 
  report u >= grid-umin and u <= grid-umax and v >= grid-vmin and v <= grid-vmax
end

to define-windows  
  ; declare the locations of the windows
  ; one large one (number 1)  on top for the ramps, 
  ; a smaller one on the lower right for graphs (number 2)
  ; and a very small one on the lower left for soft buttons or messages (number 3)
  let v-top-bot 40 ; the location of the divider between top and bottom
  let u-lt-rt .36 * min-pxcor ; the location of the divider between the two lower windows
  let buf 4  ; the buffer between windows. 
  let buf2 .5 * buf  ; half the buffer
  ; make a list of edges for each window, where window 1 is item 0
  set u-wind-lt (list (min-pxcor + buf))
  set u-wind-rt (list (max-pxcor - buf))
  set v-wind-bot (list (v-top-bot + buf2))
  set v-wind-top (list (max-pycor - buf))
  set u-wind-lt lput (u-lt-rt + buf2) u-wind-lt
  set u-wind-rt lput (max-pxcor - buf) u-wind-rt
  set v-wind-bot lput (min-pycor + buf) v-wind-bot
  set v-wind-top lput (v-top-bot - buf2) v-wind-top
  set u-wind-lt lput (min-pxcor + buf) u-wind-lt
  set u-wind-rt lput (u-lt-rt - buf2) u-wind-rt
  set v-wind-bot lput (min-pycor + buf) v-wind-bot
  set v-wind-top lput (v-top-bot - buf2) v-wind-top
  ask patches [
    set-boundaries-for 1
    if in-wind? pxcor pycor [set pcolor yellow + 4.5 stop]
;    set-boundaries-for 2
;    if in-wind? pxcor pycor [set pcolor blue   + 4.5]  
;    set-boundaries-for 3
;    if in-wind? pxcor pycor [set pcolor lime   + 4.5]
  ]
  set focus 0
end
  
to define-transforms    ; calculates m and b as in u=mx+b for window 1
  ; get transforms for window 1--note these can change during a run
  let u-center (first u-wind-lt  + first u-wind-rt ) / 2  ; calculate the u,v coordinates for the center of window 1
  let v-center (first v-wind-bot + first v-wind-top) / 2
  set mx replace-item 0 mx magnification
  set my replace-item 0 my magnification
  set bx replace-item 0 bx (u-center - x-center *  magnification)
  set by replace-item 0 by (v-center - y-center * magnification)
end

to move-ramp-old
  if move-ramp-left? [               ; flag set by an object going off to the right
    set x-center x-center - 500 / magnification
    set move-ramp-left? false ]
  if move-ramp-right? [              ; flag set by an object going off to the leaft
    set x-center x-center + 500 / magnification 
    set move-ramp-right? false ]
  define-transforms   ; reads magnification and location and computes x->u y->v transformations
  set-transforms-for 1  ; updates the transforms
  ask drawing-dots [die]       ;erase prior ramp
  draw-plc ramp ramp-color magnification / 20         ;draw the ramp 
  ask vehicles [
    place-vehicle x-val ; relocate vehicles on ramp
    ]      
end

to move-ramp
end

to support-mouse
  if not mouse-inside? [stop]   ; do nothing if the mouse is outside the view
;  set focus mouse-in-window    ; w contains the current window of the mouse
  if 2 = mouse-in-window [read-cursor-location]
  ifelse mouse-down? and not old-mouse-down? 
    [handle-mouse-click set old-mouse-down? true ]
    [ifelse not mouse-down? and old-mouse-down? 
      [handle-mouse-unclick set old-mouse-down? false ]
      [if mouse-down? and old-mouse-down? [handle-mouse-drag]]]
end  

to switch-focus-to [i]  ; sets the boundaries and transformation coefs for the current window
  if i = 0 or i > n-wind [stop]       ; do nothing if the focus is on window zero
  set focus i
  set-boundaries-for i
  set-transforms-for i
end

to set-transforms-for [i]
  let j i - 1
  set mxx item j mx         ; extract the transformation coefs
  set myy item j my
  set bxx item j bx 
  set byy item j by
end

to set-boundaries-for [i]
  let j i - 1
  set ul item j u-wind-lt   ; extract the window boundaries 
  set ur item j u-wind-rt
  set vt item j v-wind-top
  set vb item j v-wind-bot 
end

to handle-mouse-click
  switch-focus-to 1
  ; this is called only once per mouse click
  ; first check for a click in the help button area 
  if on-button [
    ask helper helper-who [set color grey ]
    display-help-message
    ask helper helper-who [set color lime ] 
    stop]   
  ; identify ramp coordinates near the mouse, if any
  let radius .1 * magnification
  if not ramp-locked? [
    set click 0          ; click informs the software of what kind of click was made. zero indicates none
    set selected-ramp-index false   ; this will be the index in ramp of the mouse is near

    let p []
    ask drawing-dots with [color = black][       ; run through the current black drawing dots to find one near the mouse
      if abs (xcor - mouse-xcor) < radius and abs (ycor - mouse-ycor) < radius [
        set click 1 
        ; find the index of the dot in ramp that produced this dot
        let x (xcor - bxx) / mxx  ; find the x,y coordinates of this point
        let y (ycor - byy) / myy
        set p list x y
        ; ramp is a list of endpoints of the ramp in x,y space
        set selected-ramp-index position p ramp ]]  ; finds [x y] in ramp, sets the index selected-ramp-index to its position
    if click = 1 [stop] ]
  
                                ; check all vehicles for one near the mouse
  if not empty? v-who [         ; skip if there are no vehicles
    let i 0                     ; v-who contains a list of the whos of current vehicles
    while [i < length v-who] [  ; check each vehicle
      let w item i v-who
      ask vehicle w [  
        if abs (xcor - mouse-xcor) < radius and abs (ycor - mouse-ycor) < radius [  ; look for a click near the vehicle
          set click 2 set speed 0 ; if a vehicle is clicked, zero its speed 
          set running? false    ; if a vehicle is clicked, the simulation is not running 
          set selected-vehicle w]]
      set i i + 1]] 
  if click = 2 [stop]           ; if click = 2 a vehicle has been selected, and its who is selected vehicle
  
  set u-click mouse-xcor  ; save the u,v coordinates of the mouse
  set v-click mouse-ycor 
  if in-wind? u-click v-click [
    set click 3 ; must be a background click
    set old-x-center x-center ; find the x,y coordinates of this point
    set old-y-center y-center]
end

to handle-mouse-unclick
  set click 0  ; indicate that the mouse is no longer dragging anything 
end

to handle-mouse-drag
  if click = 0 [stop]  ; click determines the kind of object being dragged 0: none, 1: ramp, 2: vehicle, 3: background
  ; called continuously as long as the mouse remains down
  if click = 1 and selected-ramp-index != false [    ; if a handle on the ramp has been previously selected
    if not in-wind? mouse-xcor mouse-ycor [stop] ; dont move the mouse outside the window
    let i selected-ramp-index            ; update ramp with the current location of the mouse but keep ramp in ascending x order
    if i = 1 [stop] ; don't move the bottom of the ramp, which is item 1 of rampa
    let x (mouse-xcor - bxx) / mxx       ; this will be the new x value if it is not out of order
    if abs (x) < snap [set x 0]          ; snap to zero
    let ok-to-move? false                ; turns true below if the ramp will be in ascending x order
    if i = 0 [                           ; if the moved point is on the left end
      let x1 first item 1 ramp           ; check the x-value of the second point
      if x <= x1 [set ok-to-move? true]] ; if that is not to the left of the new point it is ok to move 
    let max-i (length ramp) - 1          ; the maximum index i is one less than the number of x,y pairs in ramp
    if i = max-i [                       ; if the moved point is at the lend of the ramp list
      let x0 first item (max-i - 1) ramp ; find the x-value of the next-to-last pair in ramp
      if x0 <= x [set ok-to-move? true]] ; if this x-value is not greater than the new value, it is ok to move. 
    if i > 0 and i < max-i [             ; now check the cases for which the new point is not at either end
      let x0 first item (i - 1) ramp     ; get the x-value of the preceeding point
      let x1 first item (i + 1) ramp     ; and the x-value of the next point
      if x >= x0 and x <= x1 [set ok-to-move? true]]    ; if x falls between them, it is ok to move
    if ok-to-move? [
      let y (mouse-ycor - byy) / myy 
      if abs(y) < snap [set y 0]          ; snap to zero
      let p list x y  ; p is the [x,y] location of the mouse
      set ramp replace-item i ramp p ; replace item i of ramp with p, where i is selected-ramp-index
      move-ramp ]]        ; now redraw the ramp
  if click = 2 [
    ask vehicle selected-vehicle [
      place-vehicle ((mouse-xcor - bxx) / mxx)]  ; place the vehicle on the track at the mouse x-coordinate
    set blinking? true
    stop ]
  if click = 3 [       ; drag the x-center but not the y-center 
    set x-center old-x-center - (mouse-xcor - u-click) / mxx
;    set y-center old-y-center - (mouse-ycor - v-click) / myy
    move-ramp ]        ; uses the current x-center y-center and magnification to draw the ramp and vehiclee
end

to-report in-wind? [u v]  ; reports true if u,v is inside the focus window
  ; assumes that the focus is on the window to be tested
  report u >= ul and u <= ur and 
         v >= vb and v <= vt 
end

to-report mouse-in-window       ; reports which window the mouse is currently inside
  let u mouse-xcor let v mouse-ycor
  set-boundaries-for 1             ; switch focus in order to test
  if in-wind? u v [             ; in-wind? tests the focus window
    report 1] ; reset the focus and report 
  set-boundaries-for 2 
  if in-wind? u v [
    report 2]
  set-boundaries-for 3 
  if in-wind? u v [
    report 3]
  report 0
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;  Draw a ramp (or anything else) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to draw-plc [object c w]   ; plc stands for piecewise linear continuous line
  ; shape is a list of lists of x,y pairs
  ; the object is drawn using drawing-dots
  let pair-zero []
  if not empty? object [     ; pull off the first point
    set pair-zero first object
    set object bf object ]
  while [not empty? object][      
    let pair-one first object
    set object bf object
    draw-segment pair-zero pair-one c w
    set pair-zero pair-one ]
end
  







;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;  Draw with clipping ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to draw-segment [p0 p1 c w] ; draw a segment in the current window that connects p0 ([x0 y0]) to p1 ([x1 y1]) with clipping
  ; the line color is c and width is w. The drawing uses drawing-dots
  ; assumes that the focus is on the window where this line is to be drawn
  ; note: the following are global ul (the u-coord of the left edge), ur, vb (the v-coordinate of the bottom), and vt
  ;       the following are local, not global: vl, vr, ub, and ut
  ; updates 'latest-segment' with the a list of the who of the two endpoints or an empty list if nothing is drawn
  
  if last p0 = 0 and last p1 = 0 [set c gray + 3]     ; the ramp is gray if it on the floor, where y0=y1=0
  
  set uL first u-wind-lt 
  set uR first u-wind-rt 
  set vB first v-wind-bot 
  set vT first v-wind-top
  
  let u0 mxx * first p0 + bxx ; convert to screen coordinates
  let v0 myy * last p0 + byy
  let u1 mxx * first p1 + bxx
  let v1 myy * last p1 + byy
  let zero-in? in-wind? u0 v0  ; is point x0,y0 inside the window? 
  let one-in?  in-wind? u1 v1  ; is point x1,y1 inside?
  if zero-in? and one-in? [    ; if both are inside, connect them
    connect u0 v0 u1 v1 c w stop]
  if u0 = u1 and v0 = v1 [stop]        ; if the two points are identical, ignore
  if (u0 >= ur and u1 >= ur) or (u0 <= ul and u1 <= ul) or     ; if they are both left or right 
    (v0 >= vt and v1 >= vt) or (v0 <= vb and v1 <= vb) [stop]   ; or both above or below, do nothing. 
    
  if not zero-in? and one-in? [        ; if point zero is not inside and p1 is, swap the p0 and p1 so p0 is inside
    let t u0 set u0 u1 set u1 t        ; this insures that point zero is inside if either is
    set t v0 set v0 v1 set v1 t
    set zero-in? in-wind? u0 v0
    set one-in?  in-wind? u1 v1]       ; also update these logicals
  
  ; now consider vertical and horizontal lines
  ; describe the line between the points parametrically, vis: u = u0 + t*(u1 - u0) and v = v0 + t*(v1 - v0) for 0<=t<=1
  let points []                       ; points will contain point pairs that intersect the edge between p0 and p1 if any
  if u0 = u1 or v0 = v1 [
    if u0 = u1 [                        ; Look at the case of a vertical line that can result in divide-by-zero error
      let tT (vT - v0) / (v1 - v0)      ;   tT is the value of t at the intersection with u=ut on the top 
      if 0 <= tT and tT <= 1 [          ; Is this a good point?
        set points lput list u0 vT points]     ; If so, save the coordinates of the intersection
      let tB (vB - v0) / (v1 - v0)      ; tB is the value of t at the intersection with the bottom
      if 0 <= tB and tB <= 1 [          ; Is this a good point?
        set points lput list u0 vB points]]    ; If so, save the coordinates of the intersection
  
    if v0 = v1 [                        ; Look at the case of a horizontal line 
      let tL (uL - u0) / (u1 - u0)      ;   tL is the value of t at the intersection with v=vL on the left
      if 0 <= tL and tL <= 1 [          ; This is a good point
      set points lput list uL v0 points]
      let tr (ur - u0) / (u1 - u0)
      if 0 <= tr and tr <= 1 [
        set points lput list ur v0 points]]
    
    if length points = 0 [stop]       ; no points in the window (should be impossible)
    if length points = 1 [
      connect u0 v0 (first first points) (last first points) c w stop] ; connect p0 to the single good point
      ; the only possiblity remaining is that there are two points outside the window on opposite sides
    connect (first first points) (last first points) (first last points) (last last points) c w stop 
  ] ; end of horizontal and vertical lines

  ; Now consider sloping lines


  if zero-in? and not one-in? [        ; point zero is inside but point 1 is outside
  ; find the crossing of the line with one of the four edges and draw a line from u0 v0 to that point
  ; Again, use a parametric equation for the line: u = u0 + t*(u1-u0) and v = v0 + t*(v1-v0)  where 0 <= t <= 1
  let tR (uR - u0) / (u1 - u0)
  if tR >= 0 and tR <= 1 [             ; this is a good point, one on the right edge betwen p0 and p1
    let vR v0 + tR * (v1 - v0)
    connect u0 v0 uR vR c w stop]      ; draw from p0 to the right edge and leave
  let tL (uL - u0) / (u1 - u0)
  if tL >= 0 and tL <= 1 [             ; this is a good point on the left
    let vL v0 + tL * (v1 - v0)
    connect u0 v0 uL vL c w stop]      ; draw from p0 to the left edge and leave
  let tT (vT - v0) / (v1 - v0)
  if tT >= 0 and tT <= 1 [             ; a good point on the top
    let uT u0 + tT * (u1 - u0)
    connect u0 v0 uT vT c w stop]
  let tB (vB - v0) / (v1 - v0) 
  if tB >= 0 and tB <= 1 [             ; a good point on the bottom
    let uB u0 + tB * (u1 - u0) 
    connect u0 v0 uB vB c w stop]]

  ; here, the only possibility is that both points are outside the viewing area but might intercept with it
  set points []
  ; points will contain a list of list of pairs of "good" window edge intersections (ones between p0 and p1)
  ; Use a parametric equation for the line: u = u0 + t*(u1-u0) and v = v0 + t*(v1-v0)  where 0 <= t <= 1
  let tr (ur - u0) / (u1 - u0)
  if tr >= 0 and tr <= 1 [             ; this is a good point, one on the right edge betwen p0 and p1
    let vr v0 + tr * (v1 - v0)
    set points lput list ur vr points] ; put the ur,vr pair in the list points ;
  let tl (ul - u0) / (u1 - u0)
  if tl >= 0 and tl <= 1 [             ; this is a good point on the left
    let vl v0 + tl * (v1 - v0)
    set points lput list ul vl points] ; add this pair to the list points
  let tt (vt - v0) / (v1 - v0)
  if tt >= 0 and tt <= 1 [             ; a good point on the top
    let ut u0 + tt * (u1 - u0)
    set points lput list ut vt points] ; add it to the list points
  let tb (vb - v0) / (v1 - v0) 
  if tb >= 0 and tb <= 1 [             ; a good point on the bottom
    let ub u0 + tb * (u1 - u0)
    set points lput list ub vb points] ; add it to the list points
  
  ; here, points should consist of zero or two pairs of points
  if empty? points [stop ]      ; escape without drawing anything--the line between p0 and p1 never intersects the view
  if length points = 2 [        ; this better be always true here, but it is included just in case
    let u2 first first points   ; here the line between p0 and p1 intercepts the window at the two pairs in points
    let v2 last  first points
    let u3 first last  points        
    let v3 last  last  points
    connect u2 v2 u3 v3 c w ]
end

to connect [u0 v0 u1 v1 c wide] 
  ; uses drawing-dots to connect u0,v0 to u1,v1 with a line of color c and width wide
  if u0 = u1 and v0 = v1 [stop] ; don't bother with points on top of each other
  let w 0 let w1 0
  create-drawing-dots 1 [
    set size .06 * magnification 
    set shape "square" set color black
    set label-color red
    set label word precision ((u0 - bxx) / mxx) 2 " m  "
    ifelse on-edge? u0 v0 [ht][st]   ; hide the black dot and its label if it is on the edge
    setxy u0 v0
    set w who]
  create-drawing-dots 1 [
    set size .06 * magnification 
    set shape "square" set color black
    ifelse on-edge? u1 v1 [ht][st]
    setxy u1 v1
    set w1 who
    create-link-with drawing-dot w [
      set thickness wide
      set color c ]]
end

to-report on-edge? [u v]
  report (u = ul) or (u = ur) or
         (v = vb) or (v = vt)
end  
  
to-report vehicle-info [pairs x]    ; returns y(x) and angle: the height and dirction of the vehicle
  ;  on a ramp that is a plc defined by pairs, an ordered list of x,y lists (uses problem coordinates)
  if x < first first pairs [report list 0 90]
  if x > first last  pairs [report list 0 90] ; if x is less than the first x or greater than the last, return zero
  let i 1                             ; for the inteval between each pair defined by their x-values
  while [i < length pairs ][
    let x0 first item (i - 1) pairs 
    let x1 first item i pairs
    if x >= x0 and x <= x1 [ ; if x is not less than the previous x and not greater than the current one
      ; x must be between pair i-1 and i, so interpolate
      let y0 last item (i - 1) pairs
      let y1 last item i pairs
      if x0 = x1 [ report list (.5 * (y0 + y1)) 0] ; If the points are at the same x-value, return the average of the ys
      let direction atan (x1 - x0) (y1 - y0)
      report list (y0 + (x - x0) * (y1 - y0) / (x1 - x0)) direction]
    set i i + 1 ]
end

to-report track-height [pairs x]    ; returns y(x) : the height of the track defined by pairs at x
  ; pairs is an ordered list of x,y lists (uses problem coordinates) "ramp" is the usual value
  if x < first first pairs [report 0]
  if x > first last  pairs [report 0] ; if x is less than the first x or greater than the last, return zero
  let i 1                             ; for the inteval between each pair defined by their x-values
  while [i < length pairs ][
    let x0 first item (i - 1) pairs 
    let x1 first item i pairs
    if x >= x0 and x <= x1 [ ; if x is not less than the previous x and not greater than the current one
      ; x must be between pair i-1 and i, so interpolate
      let y0 last item (i - 1) pairs
      let y1 last item i pairs
      if x0 = x1 [ report .5 * (y0 + y1) ] ; If the points are at the same x-value, return the average of the ys
      report  (y0 + (x - x0) * (y1 - y0) / (x1 - x0)) ]
    set i i + 1 ]
end

to run-vehicles
  ; using the starting position, move vehicle forward only if running? is true
  if running? and not old-running? [   ; must be the first cycle 
    set old-running? true       
    set data-series []     ; erase prior data series (this list will be exported at the end of the run)
    set saved-starting-x dist-from-zero 
    set start-height (precision height 2) ]          ; save the starting height
  set time time + dt
  ask vehicles [
    let ch cos heading
    let a 0
    let f friction * .4
    ifelse speed > 0 
        [set a g * ( sin heading  - f * ch) ] ; the accleration to the right
        [set a g * ( sin heading  + f * ch) ] ; the acceleration to the left
    let mid-speed speed + .5 * a * dt              ; estimate the speed mid-interval
    set x-val x-val + mid-speed * ch * dt          ; use the mid-interval speed to get the final x-value
    set speed mid-speed + .5 * a * dt              ; update the speed
    ifelse abs (speed - 0 ) > .0001                ; stop the car if it is at rest for more than ten intervals
      [set countdown loops-at-zero]
      [set countdown countdown - 1 ]
    if countdown < 1 [
      set final-position x-val
      handle-run-end ]
    place-vehicle x-val]
end

to handle-run-end      ; This is called once when the vehicle has not moved for a while, indicating that the run is over. Called by run-vehicles
  set running? false   ; this stops the calculations and unlocks the sliders
  set waiting-for-setup? true   ; require the next user action be pressing the setup button
  clear-output         ; erase previous instructions
  update-score         ; computes and displays the score
  get-next-step        ; changes the step and level depending on the just-computed score
  setup-game           ; sets up the various controls for this new step and level.
;  show-target          ; shows the target
end

;to-report vertical-location [x]               ; returns the height of the ramp at x
;end              replaced by track-height
    
to setup-new-run
  show-target          ; shows the new target
  set time 0
  erase-data
  set run-number run-number + 1 
  ask vehicles [set color item (run-number mod 6) vehicle-colors]
  switch-focus-to 2  ; reset the grid
  set blinking? false
  set grid-xmin 0 set grid-xmax 4 
  set grid-ymin -2 set grid-ymax 5
  rescale-grid
  
  switch-focus-to 1
  set x-center 1.35
  move-ramp
  if not empty? v-who [
    let i 0 
    while [i < length v-who][
      ask vehicle (item i v-who) [
        place-vehicle saved-starting-x 
        set speed 0]
      set i i + 1]]
  set running? false ; the simulation is not recording
  set old-running? false  ; used to trap the first cycle (probably redundant)
  set saved-time-series []  ; this contains the data to be exported
;  set waiting-for-setup? false  ; ignore this procedure if the next user action must be pressing the setup button
  show-target      ; shows the target for this level and step
  clear-output
  pretty-print instructions
  tick
end

to show-target   ; draws the target for the current level and step. 
  ; Must set step and level first, as well as target value and target radius (in problem space, e.g., meters)
  switch-focus-to 1    ; set focus on the ramp
  ask marker marker-1 [
    set x-val target - target-radius
    set y-val track-height ramp x-val
    let u mxx * x-val + bxx
    let v myy * y-val + byy + 6
    setxy u v st ]
;    ifelse in-grid? u v 
;      [setxy u v st ] [ht]]
  ask marker marker-2 [
    set x-val target + target-radius
    set y-val  track-height ramp x-val
    let u mxx * x-val + bxx
    let v myy * y-val + byy + 6
    setxy u v st ]
;    ifelse in-grid? u v 
;      [setxy u v st ][ht]]
  set waiting-for-setup? false
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;; scale and grid-drawing routines ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to draw-grid  ; draws the grid 
  ; inputs (all globals) are the grid screen boundaries, the desired ranges of x and y, the intended number of tic marks in the x-direction, 
  ; the axis labels, and the colors of the grid and labels
  ; Draws and labels the graphing grid 
  ; outputs are the transformation coefs which are stored in the second position in their respective lists
  ask grid-dots [die] ; clear the grid
  draw-verticals   ; draws the vertical lines and the x-axis
  draw-horizontals ; draws the horizontal lines and the y-axis
end

to draw-verticals ; x-axis
  let xTarget (grid-umax - grid-umin ) * patch-size / grid-separation       ;  sets the target number of tics based on the size of the graphing area
                                                      ; allocates about grid-separation pixels per tic
  let a ticMarks grid-xMin grid-xMax xTarget        ; a now contains graph-xmin, graph-xmax, and n-xtics 
  set grid-xmin first a set grid-xmax item 1 a
  ; compute the transformation coeficients in u=mx+b
  set mxx (grid-umax - grid-umin) / (grid-xmax - grid-xmin)
  set bxx grid-umin - mxx * grid-xmin
  set mx replace-item 1 mx mxx  ; store these transformation coefs
  set bx replace-item 1 bx bxx
  let n-xtics last a
  let dxx (grid-xmax - grid-xmin) / (n-xtics - 1)
  let x grid-xmin
  repeat n-xtics [   ; draw and label the verticals one at a time
    let w 0 
    let u mxx * x + bxx
    create-grid-dots 1 [
      set size 0 
      setxy u grid-vmax  ; place at the top of the grid
      set w who ]
    create-grid-dots 1 [
      set size 0 
      setxy u grid-vmin - tic-length
      create-link-with grid-dot w [
        set thickness line-width
        set color grid-color
        if abs (x - grid-xmin ) < .01 * dxx or 
            abs (x - grid-xmax ) < .01 * dxx [
          set thickness 2 * line-width ]]]   ; make edges wider
    create-grid-dots 1 [      ; used to place the value 
      set size 0 
      set label precision x 3
      set label-color grid-label-color
      setxy u + 5 grid-vmin - (tic-length + 5)]
    set x x + dxx ]
  create-grid-dots 1 [    ; label the axis
    set size 0
    let u .5 * (grid-umax + grid-umin) + 2 * length grid-xlabel
    setxy u grid-vmin - 20
    set label grid-xlabel 
    set label-color grid-label-color]
end
      
to draw-horizontals ; y-axis
  let yTarget (grid-vmax - grid-vmin ) * patch-size / grid-separation       ;  sets the target number of tics based on the size of the graphing area
                                                      ; allocates about grid-separation pixels per tic
  let a ticMarks grid-yMin grid-yMax yTarget        ; a now contains graph-xmin, graph-xmax, x-interval, and n-xtics 
  set grid-ymin first a 
  set grid-ymax item 1 a
  ; compute the transformation coeficients in u=mx+b
  set myy (grid-vmax - grid-vmin) / (grid-ymax - grid-ymin)
  set byy grid-vmin - myy * grid-ymin
  set my replace-item 1 my myy  ; store these transformation coefs
  set by replace-item 1 by byy
  let n-ytics last a
  let dyy (grid-ymax - grid-ymin) / (n-ytics - 1)
  let y grid-ymin
  repeat n-ytics [   ; draw and label the horizontals one at a time
    let w 0 
    let v myy * y + byy
    create-grid-dots 1 [
      set size 0 
      setxy grid-umax v ; place at the right of the grid
      set w who ]
    create-grid-dots 1 [
      set size 0 
      setxy (grid-umin - tic-length) v
      set label precision y 3
      set label-color grid-label-color
      create-link-with grid-dot w [
        set thickness line-width
        set color grid-color
        if abs (y - grid-ymin ) < .01 * dyy or 
            abs (y - grid-ymax ) < .01 * dyy [
          set thickness 2 * line-width ]]]   ; make edges wider
    set y y + dyy ]
  create-grid-dots 1 [ ; label the y-axis
    set size 0 
    set label y-axis
    set label-color grid-label-color
    let u grid-umin + 5 * length y-axis
    setxy u grid-vmax + 5]
end 

to-report ticMarks [zMin zMax targetNumber]
     ; Computes the scaling parameters.
     ; Inputs are:
     ;     the beginning of the scale
     ;     The end of the scale
     ;     The target number of tic marks in the scale
     ; returns a list:
     ;    The first item is the beginning of the scale (rounded down to an even number)
     ;    The second item is the end of the scale (rounded up)
     ;    The third item is the actual number of tics (differnet from nTics)
   if ( zMax < zMin ) [                       ; swap if in the wrong order
     let z zMax
     set zMax zMin
     set zMin z ]
      ; compute the target interval between scale divisions (tic marks) in problem coordinates.
      ; note that if there are N tic marks, there are N-1 intervals.
   let dz  (zMax - zMin) / (targetNumber - 1) ; the value of the interval for the target number of tics
   let y log dz 10                            ; compute the log base 10 of dz
   let a floor y                              ; round y down to the nearest smaller integer
   let z y - a                                ; z is the fractional part of the log
   let r 0
   ifelse z < .15                             ; if z is less than .15 set r to 1
     [set r 1]
     [ifelse z < .5                           ; otherwise if it is less than .5 set r to 2
        [set r  2]
        [ifelse  z < .85                      ; otherwise if it is less that .85 set r to 5
          [set r 5 ]                          ; and if all else fails, set r to 10
          [set r 10 ]]]                       ; r is the nearest 'nice' number to z: 1, 2, 5 or 10                        
   set dz  r * 10 ^ a                         ; dz is now the "corrected" tic interval
   let k floor (zMin / dz)                  
   let lowtic k * dz
   let ntics 1 + ceiling (zMax / dz ) - k     ; the actual number of tic marks
   let hitic lowtic + dz * (ntics - 1)  
   report (list lowtic hitic ntics)
end

to place-point [x y c]   ; places the point x,y on the grid in window 2 as a dot of color c
  switch-focus-to 2
  let f .05 ; a fraction of the grid scale 
  if x > (1 - f) * grid-xmax - f * grid-xmin [ ; if near the right edge...
    set grid-xmax 1.5 * grid-xmax  ; the x-axis always starts at zero time
    rescale-grid ]
  if y < grid-ymin + f * (grid-ymax - grid-ymin) [ ; if near the bottom...
    set grid-ymin grid-ymin - .5 * (grid-ymax - grid-ymin)
    rescale-grid]
  if y > (1 - f) * grid-ymax - f * grid-ymin [     ; if near the top
    set grid-ymax grid-ymax + .5 * (grid-ymax - grid-ymin)
    rescale-grid]
  let u mxx * x + bxx
  let v myy * y + byy
  create-graph-dots 1 [ht
    set x-val x set y-val y 
    set color c
    set size 5 set shape "dot"
    if in-grid? u v [ st
      setxy u v ]]
end
    
to update-y-axis
end

to rescale-grid    ; redraws the grid and any points using the globals grid-xmin, grid-ymin,  etc....
  switch-focus-to 2
  draw-grid
  ask graph-dots [
    let u mxx * x-val + bxx
    let v myy * y-val + byy
    ifelse in-grid? u v 
      [st setxy u v ]
      [ht]]    
end

to hide-graph
  ask graph-dots [ht]
  ask grid-dots [die]
end

to erase-data
  ask graph-dots [die]
end

to add-vehicle
  create-vehicles 1 [
;    switch-focus-to 1
    ht  
    set v-who lput who v-who ; add this to the list of vehicle whos
    let n ((length v-who) - 1) mod 6
    set color red
    set shape item n vehicle-shapes
    set mass item n vehicle-masses
    set x-val item n vehicle-starts  ; beginning location of vehicle
    set offset item n vehicle-offsets
    set size-100 item n vehicle-sizes
    set spring-left? false
    set spring-right? false
    place-vehicle x-val]
end

to remove-vehicle ; removes the selected vehicle
  if not blinking? [stop]   ; some vehicle is selected only if blinking? is true
  if length v-who < 2 [stop] 
  ask vehicle selected-vehicle [die]
  ; now correct v-who list by removing the selected vehicle's who.
  let i position selected-vehicle v-who
  set v-who remove-item i v-who
  set blinking? false
  set selected-vehicle first v-who
end

to start-run
  if waiting-for-setup? [stop]  ; ignore this procedure if the next user action must be pressing the setup button
  if not data-saved? [
    if user-yes-or-no? "If you run now, you will lose data. Do you want to save your data before running? " [stop]]
  set data-saved? false
  erase-data
  set running? true
  set blinking? false
  set time 0
end

to read-cursor-location  ; used if the cursor is in the graphing area
  let u mouse-xcor let v mouse-ycor
  if not in-grid? u v [
    ask readers [ht]
    stop]
  switch-focus-to 2
  let x precision ((u - bxx) / mxx) 2
  let y precision ((v - byy) / myy) 2
  ask readers [ st
    set label (word "time: " x " distance: " y)
    setxy u v]
end

to autoscale
  ; assume that x-val, y-val in the graph dots contain the points to be plotted
  ; find the min and max of each
  if count graph-dots = 0 [stop]    ; this could cause errors
  set grid-xmin 1e20  set grid-xmax -1e20 
  set grid-ymin 1e20  set grid-ymax -1e20
  ask graph-dots [
    if x-val < grid-xmin  [set grid-xmin x-val ]
    if x-val > grid-xmax  [set grid-xmax x-val ]
    if y-val < grid-ymin  [set grid-ymin y-val ]
    if y-val > grid-ymax  [set grid-ymax y-val]]
  ; grid-xmin grid-xmax grid-ymin and grid-ymax now contain the min-max for the two axes
  ; now rescale the grid using the new limits. Calculate the transforms mxx, etc. 
  switch-focus-to 2
  draw-grid
  ; and finally, move the dots to their new positions
  ask graph-dots [
    setxy (mxx * x-val + bxx) (myy * y-val + byy)]
end

to capture-final-state     ; 
  set old-running? false
  ask vehicle first v-who [
    update-run-series (precision x-val 2) ]
;  update-data-series  ; makes the list of time-series data available 
end

to get-next-step    ; determines whether the student stays at this step, goes up, or goes down
                    ; carries over to the next or previous level
   let upper-break 2 * max-score / 3  ; the minimum score to advance
   let lower-break max-score / 4  ; the minimum score to stay at this step

   if score-last-run > upper-break [
     clear-output
     pretty-print (word "Congratulations! You earned " score-last-run " points! You advance a step")
     set step step + 1
     if step > n-steps [
       clear-output
       pretty-print (word "Congratulations! You earned " score-last-run " points! You advance to a new level!!")
       ifelse level <= max-level
         [set step 1
          set level level + 1 ]
         [set level n-steps 
           clear-output 
           pretty-print (word "Incredible!! You have reached the highest step at the hightes level. You are a winner." )
           ]]      ; if the student is on the last level, keep at the highest step. 
     stop]  ; 
   if score-last-run > lower-break [
     clear-output
     pretty-print (word "OK! You earned " score-last-run " points. Try a similar problem.")]
   
   if score-last-run <  lower-break [
     clear-output
     let m (word "Not so good. You score " score-last-run " points.")
     if step > 1 or level > 1 [set m word m "Try an easier problem."]
     pretty-print m
     set step step - 1 
     if step < 1 [
       ifelse level = 1
         [set step 1]
         [set level level - 1
           set step n-steps - 1]]]
end

to setup-game     ; sets all the controls for the current level and step
  setup-game-level
  setup-game-step
end

to setup-game-level ; setup the game for the current level.
  if level = 1 [
    set instructions "Make the car stop in the center of the red area by changing the car's starting position."
    set instructions word instructions " Save your data each run. You will need it later."
    set friction .5
    set old-friction friction
;    set old-air-friction air-friction
    set friction-locked? true
    set air-friction-locked? true
    set starting-position-locked? false
    set ramp-locked? true
    set starting-position-max -1
    set starting-position-min -1
    set max-score  100   ; the maximum score for one run that is possible for this level
    set n-steps  4   
    set target-radius-max .6 ; the distance between the center and edge of the target for step 1
    set target-radius-min .2 ; the distance for the highest step in this level
    set target-max 2  ; each step, the target is set at random between target-max and target-min
    set target-min 2]   ; to defeat random placement of the target, set min to max. 
  
  if level = 2 [
    set instructions "Make the car stop in the center of the red area by changing the car's starting position."
    if step = 1 [set instructions word instructions " Watch out!! The red band now moves each trial."]
    set friction .5
    set old-friction friction
;    set air-friction .2
    set friction-locked? true
    set air-friction-locked? true
    set starting-position-locked? false
    set ramp-locked? true
    set max-score  150   ; the maximum score for one run that is possible for this level
    set n-steps  4
    set starting-position-max -1
    set starting-position-min -1
    set target-radius-max .4 ; the distance between the center and edge of the target for step 1
    set target-radius-min .2 ; the distance for the highest step in this level
    set target-max 3  ; each step, the target is set at random between target-max and target-min
    set target-min 1]   ; to defeat random placement of the target, set min to max. 
  
  if level = 3 [
    set instructions "Now the friction has been reduced. How does this change your strategy?"
    set friction .3
    set old-friction friction
;    set air-friction .2
    set starting-position-locked? false    
    set friction-locked? true
    set air-friction-locked? false
    set ramp-locked? true
    set max-score  200   ; the maximum score for one run that is possible for this level
    set n-steps  4
    set starting-position-min -1
    set starting-position-min -1
    set target-radius-max .4 ; the distance between the center and edge of the target for step 1
    set target-radius-min .2 ; the distance for the highest step in this level
    set target-max 2     ; each step, the target is set at random between target-max and target-min
    set target-min 2]   ; to defeat random placement of the target, set min to max. 
  
  if level = 4 [
    set instructions "Now made the car stop in the center of the red area by changing the friction. You cannot change the car's starting position."
    set friction .5
    set old-friction friction
;    set air-friction .2
    set starting-position-locked? true    
    set friction-locked? false
    set air-friction-locked? false
    set ramp-locked? true
    set max-score  250   ; the maximum score for one run that is possible for this level
    set n-steps  4
    set starting-position-min -1
    set starting-position-min -1
    set target-radius-max .4 ; the distance between the center and edge of the target for step 1
    set target-radius-min .2 ; the distance for the highest step in this level
    set target-max 1     ; each step, the target is set at random between target-max and target-min
    set target-min 3]   ; to defeat random placement of the target, set min to max. 

end

to setup-game-step   ; sets the values of controls that change with each step--the target and starting point widths
  set target random-between target-max target-min
  set target-radius target-radius-max + (target-radius-min - target-radius-max ) * (step - 1) / (n-steps - 1)
end
  
to-report random-between [a b]
  report a + random-float (b - a)
end

to pretty-print [mess]   ; prints the message mess with breaks at spaces and no more than line-max characters per line 
  if mess = 0 [stop]
  if empty? mess [stop]
  let line ""
  if length mess <= output-width [
    output-print mess stop]
  let i 0 let n -1
  while [i < output-width ][
    let ch item i mess
    if ch = " " [set n i ]    ; save the index of the space
    set i i + 1 ]             ; at this point n contains -1 indicating no spaces, or the index of the first space
  ifelse n = -1 
    [set line substring mess 0 output-width    ; print all output-width characters
      set mess substring mess output-width length mess ]
    [ifelse n = output-width 
      [set line substring mess 0 n 
        set mess substring mess n length mess]
      [set line substring mess 0 n 
        set mess substring mess (n + 1) length mess]]
  output-print line
  pretty-print mess
end

to update-score  ; called once by handle-run-end at the end of a run
  ; input is final-position, generated by run-vehicles
  set score-last-run 0
  if abs (final-position - target) < target-radius [
;   use a scoring algorithm with a flat max that drops to zero when the user is off by target-radius: max*(1+cos (π*miss/radius)/2 
     set score-last-run .5 * max-score * (1 + cos (180 * abs (final-position - target) / target-radius))
     set score-last-run 5 * round (.2 * score-last-run )]   ; round to the nearest 5 points
  set total-score round (total-score + score-last-run)
  set score-last-run round score-last-run
end             

to display-help-message 
  ; generates context-sensitive hints
  ; context is generated by step, level, and messages-shown, a list of the number of messages shown at level (item + 1)
  let number-shown-already item (level - 1) messages-shown
  set messages-shown replace-item (level - 1) messages-shown (number-shown-already + 1)
  let m "Ask your teacher for help."
  if level = 1  [
    set number-shown-already number-shown-already mod 6
    if number-shown-already = 0 [
      set m "Press the 'Start' button to start the car rolling down the ramp. "]
    if number-shown-already = 1 [
      set m "Before starting a run, move the car to where you think it will have enough energy to reach the center of the red band."]
    if number-shown-already = 2 [
      set m "After a good score you advance by one step and the red band gets smaller. "]    
    if number-shown-already = 3 [
      set m "Before you can make a run, you need to press the 'Setup Run' button. "]    
    if number-shown-already = 4 [
      set m "The 'Setup Run' button returns the car to its previous starting position. "]  
    if number-shown-already = 5 [
      set m "After each run, save your data by pressing the 'Save Data' button. " ]]
    
  if level = 2 [
    set number-shown-already number-shown-already mod 4
    if number-shown-already = 0 [    
      set m "At this level, the band moves around each run." ]    
    if number-shown-already = 1 [
      set m "Hint: Pay attention to the starting height above the floor. "]    
    if number-shown-already = 2 [
      set m "Hint: The graph at right will tell you where to start the car. "]    
    if number-shown-already = 3 [
      set m "Hint: Look carefully at the graph on the right that shows starting height and distance traveled. "
      set number-shown-already -1 ]  ]
    
  if level = 3 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "At this level, the friction is lower than before." ]  
    if number-shown-already = 1 [    
      set m "Now when you save data, the points will trace out a different graph of distance against starting height." ] 
    if number-shown-already = 2 [    
      set m "Hint: use the new graph of distance against starting height to predict starting positions at this level." ] ]       
  
  if level = 4 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "At this level, you cannot change the starting position of the car--you have to change friction." ]  
    if number-shown-already = 1 [    
      set m "Hint: Change the horizontal axis of the graph on the right to friction." ] 
    if number-shown-already = 2 [    
      set m "Hint: Use the graph that shows the distance the car travels as it depends on friction." ]]        
    
  pretty-print m
  ; update the messages-shown list
  set messages-shown replace-item (level - 1) messages-shown (number-shown-already + 1)
  set number-of-hints reduce + messages-shown
end

to save-data ;
  data-export:make-model-data
  data-export:make-research-data      ; this is new
  set data-saved? true
end

to data-export:make-research-data
end

;to save-for-output ; this program updates saved-time-series, a list of lists containing [t, x, y, speed] for every .25 sec
  ; it also rounds off the variables to a reasonable number of digits
;  ask vehicle (first v-who) [  ; this version only suports one vehicle
;    let t precision time 3
;    set total-distance (precision x-val 2)
;    let y precision y-val 2
;    let s precision speed 2
;    let point (list t total-distance y s)
;    set saved-time-series lput point saved-time-series ]
;  set saved-height precision height 2
;  set saved-total-time precision time 2
;end


;;;
;;; Start of data-export methods
;;;
;;; *** setup-data-export
;;;
;;; Structure definitions for setup-data-export method:
;;;
;;; computational-inputs and representational-inputs
;;;   label, units, min, max, visible
;;;
;;;   label: string
;;;   units: string
;;;   min: number
;;;   max: number
;;;   visible: boolean
;;;
;;;   alternate form when value of units is "categorical"
;;;   label units [categorical-type1 categorical-type2 ...]  visible
;;;
;;; computational-outputs
;;;   label, units, min, max, visible
;;;
;;;   label: string
;;;   units: string
;;;   min: number
;;;   max: number
;;;   visible: boolean
;;;
;;; student-inputs
;;;   label, unit-type
;;;
;;;   label: string
;;;   unit-type: string
;;;
;;; model-information
;;;   name, filename, version
;;;
;;; time-series-data (an array of lists)
;;;   label, units, min, max
;;;
;;; Edit setup-data-export and call when your model is setup
;;;

to setup-data-export
  let computational-inputs [
    [ "Start height" "m" 0 1.5 true ]
    [ "Friction" "" 0 1 true ]]
  let representational-inputs [ ]
  let computational-outputs [
    [ "End distance" "s" 0 6 true ]]
  let student-inputs [ ]
  let model-information [
    [ "ramp" "RampGame.v2.nlogo" "Sept " ] ]
  let setup (list computational-inputs representational-inputs computational-outputs student-inputs model-information [])
  data-export:initialize setup
end

;;;; The following is Bob's imagined code for setting up the research data export. 
;;;; The variables are are simpler than the data export--just single values. 
;;;; This calls data-export:initialize-research which needs to be written--I've just made a stub so it compiles. 

to setup-research-export
  let research-data [
    [ "Time" ]
    [ "Level"  ]
    [ "Step" ]
    [ "Score this run" ]
    [ "Target position" ]
    [ "Hints used" ]] 
  data-export:initialize-research research-data 
end

to data-export:initialize-research [data]
end

;;;
;;; update-run-series 
;;;    call once at the end of a run
;;;    pass in any needed values as arguments if they are not accessible as global variables
;;;

to update-run-series [endpoint]    
  let computational-inputs     list start-height friction  
  let representational-inputs []
  let computational-outputs   ( list endpoint )
  let student-inputs          []
  let run-series-data ( list computational-inputs representational-inputs computational-outputs student-inputs )
  data-export:update-run-series run-series-data
end

;;;;  Bob's imagined way of loading data for research
;;;;  Research-data contains: 
;;;;     "Time" 
;;;;     "Level"  
;;;;     "Step" 
;;;;     "Score last run" 
;;;;     "Target position" 
;;;;     "Hints used" 
to update-research-data         
  let research-data (list timer level step score-last-run target number-of-hints)
  data-export:update-research-data research-data
end

to data-export:update-research-data [x]   ;;;;
end

;;;
;;; update-data-series [ data-series ]
;;;    call once at the end of a run
;;;    data series is a list: [time distance height speed] generated each time the display is updated
;;;    pump 
;;;    pass in any needed values as arguments if they are not global variables
;;;

;to update-data-series 
;  data-export:update-data-series data-series
;end

;;;
;;; update-inquiry-summary [ inquiry-summary ]
;;;
;;; inquiry-summary is an optional custom string generated by the application
;;;

;;;;to update-inquiry-summary
;;;;  data-export:update-inquiry-summary []
;;;;end

;;;
;;; To test in NetLogo:
;;;
;;;
;;; After running the model call the method data-export:make-model-data:
;;; 
;;;   data-export:make-model-data
;;;
;;; This will update the global variable: data-export:model-data
;;;
;;; Now print data-export:model-data which contains the JSON data available for export:
;;;
;;;   data-export:make-model-data print data-export:model-data
;;;
;;;
;;; end of data-export methods
;;;
@#$#@#$#@
GRAPHICS-WINDOW
10
16
645
464
300
200
1.0414
1
10
1
1
1
0
0
0
1
-300
300
-200
200
0
0
0
ticks
30.0

BUTTON
10
10
112
44
On/Off
Go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
18
331
115
365
Setup New Run
setup-new-run
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
18
366
197
399
Start
Start-run
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
17
398
196
431
Friction
Friction
0
1
0.5
.01
1
NIL
HORIZONTAL

TEXTBOX
21
431
195
458
This slider sets the friction in the car's wheels. 
10
0.0
1

MONITOR
213
10
329
55
Height above Floor
word precision Height 2 \" m\"
17
1
11

MONITOR
329
10
515
55
Distance to the right of zero
word precision Dist-from-zero 2 \" m\"
17
1
11

BUTTON
541
395
626
429
NIL
Autoscale
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

OUTPUT
215
209
636
454
14

MONITOR
19
212
121
269
Total Score
Total-Score
17
1
14

MONITOR
122
224
211
269
Score last run
Score-last-run
17
1
11

MONITOR
22
281
79
326
NIL
Level
17
1
11

MONITOR
77
281
134
326
NIL
Step
17
1
11

MONITOR
134
281
211
326
Max score
Max-score
17
1
11

BUTTON
115
332
198
365
Save data
save-data
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

ambulance
true
0
Rectangle -7500403 true true 30 90 210 195
Polygon -7500403 true true 296 190 296 150 259 134 244 104 210 105 210 190
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Circle -16777216 true false 69 174 42
Rectangle -1 true false 288 158 297 173
Rectangle -1184463 true false 289 180 298 172
Rectangle -2674135 true false 29 151 298 158
Line -16777216 false 210 90 210 195
Rectangle -16777216 true false 83 116 128 133
Rectangle -16777216 true false 153 111 176 134
Line -7500403 true 165 105 165 135
Rectangle -7500403 true true 14 186 33 195
Line -13345367 false 45 135 75 120
Line -13345367 false 75 135 45 120
Line -13345367 false 60 112 60 142

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

ball
false
0
Circle -7500403 true true 0 0 300

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

bus
true
0
Polygon -7500403 true true 15 206 15 150 15 120 30 105 270 105 285 120 285 135 285 206 270 210 30 210
Rectangle -16777216 true false 36 126 231 159
Line -7500403 true 60 135 60 165
Line -7500403 true 60 120 60 165
Line -7500403 true 90 120 90 165
Line -7500403 true 120 120 120 165
Line -7500403 true 150 120 150 165
Line -7500403 true 180 120 180 165
Line -7500403 true 210 120 210 165
Line -7500403 true 240 135 240 165
Rectangle -16777216 true false 15 174 285 182
Circle -16777216 true false 48 187 42
Rectangle -16777216 true false 240 127 276 205
Circle -16777216 true false 195 187 42
Line -7500403 true 257 120 257 207

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

button
true
5
Rectangle -7500403 true false 30 75 285 225
Rectangle -10899396 true true 45 90 270 210

car
true
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

engine
true
0
Rectangle -7500403 true true 30 105 240 150
Polygon -7500403 true true 240 105 270 30 180 30 210 105
Polygon -7500403 true true 195 180 270 180 300 210 195 210
Circle -7500403 true true 0 165 90
Circle -7500403 true true 240 225 30
Circle -7500403 true true 90 165 90
Circle -7500403 true true 195 225 30
Rectangle -7500403 true true 0 30 105 150
Rectangle -16777216 true false 30 60 75 105
Polygon -7500403 true true 195 180 165 150 240 150 240 180
Rectangle -7500403 true true 135 75 165 105
Rectangle -7500403 true true 225 120 255 150
Rectangle -16777216 true false 30 203 150 218

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tiny dot
true
0
Circle -7500403 true true 135 135 30

train
false
0
Rectangle -7500403 true true 30 105 240 150
Polygon -7500403 true true 240 105 270 30 180 30 210 105
Polygon -7500403 true true 195 180 270 180 300 210 195 210
Circle -7500403 true true 0 165 90
Circle -7500403 true true 240 225 30
Circle -7500403 true true 90 165 90
Circle -7500403 true true 195 225 30
Rectangle -7500403 true true 0 30 105 150
Rectangle -16777216 true false 30 60 75 105
Polygon -7500403 true true 195 180 165 150 240 150 240 180
Rectangle -7500403 true true 135 75 165 105
Rectangle -7500403 true true 225 120 255 150
Rectangle -16777216 true false 30 203 150 218

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
true
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
