; SlolamGameB
; Sept 23, 2013
; Based on SuperRamp
; Bob Tinker
; Copyright, the Concord Consortium

extensions [sensor]         ; loads the extension that support probes through the LabQuest Mini from Vernier

globals [

; Control logic  
  dt                    ; the time step--the time between samples
  time                  ; the current time since starting the run
  start-hit?

  ; logicals that guide the user through the run-analyze-setup-run cycle
  running?              ; true when data are being collected
  waiting-to-start?     ; used to turn on the display of the height on the vertical axis
  waiting-to-analyze?
  waiting-to-setup?    ; used to force the user to press setup before running.  
  connected? 
  
  old-mouse-down? 
  output-width          ; the width in characters of the output box
  old-duration
  starting?             ; true only in the beginning--allows a first screen to be shown. 
  run-number
  u-click v-click       ; the u,v coordinates of the background where the mouse clicked

; Graph variables
  wind-umin wind-umax wind-vmin wind-vmax  ; define the graphing window
  mx bx my by           ; transformation coefs: u=mx*x + bx and v=my*y + by (u,v are screen coord; x,y are problem coords)
  grid-umax grid-umin   ; the boundaries of the graphing grid (as opposed to window boundaries)
  grid-vmax grid-vmin
  edge edge+            ; the distance between the window and the grid in screen units 
  grid-xmin grid-xmax grid-xlabel
  grid-ymin grid-ymax grid-ylabel
  grid-color grid-label-color
  graph-color
  grid-separation       ; target number of pixels per grid line
  tic-length            ; number of pixels the tic extends beyond the axis
  line-width            ; width of lines in the grid.
  
; Game variables
  total-score           ; score since the beginning
  current-score         ; score updated during a run--when run is over, becomes the score for that run
  level                 ; the current level
  step                  ; the current step in the current level
  messages-shown        ; a list of the number of messages shown to the user at each level
  instructions          ; Text. Set for each level. 
  number-of-hints       ; the number the student used
  max-score             ; the maximum score a user could earn for the current level
  n-steps               ; the number of steps in the current level
  target-width-max      ; the maximum road width at this step, corresponding to step 1
  target-width-min      ; the minimum road width at this step, correspondind to step n-steps
  target-width          ; the road width for this level and step
  max-level             ; the number of levels in the game
  param-a param-b
  param-c param-d
  graph-type
  
  ;research data
  aborts                ; a list of aborts 
  points                ; a list of (time,height) pairs
  state                 ; a list of state variables. useful in restoring the state from memory. 
  wrong-button-count 
  data                  ; a list of data for each run, each consisting of the state, aborts, and other data just before a run. 
  file-name
  timer-offset          ; used to determine total running time since starting, even if stopped and restarted later
  ]

breed [road-dots road-dot]
breed [grid-dots grid-dot]            ; used for drawing the graphing grid. 
breed [graph-dots graph-dot]          ; used for graphs
breed [drawing-dots drawing-dot]      ; used for various tasks.


graph-dots-own [run-num x-val y-val velocity]  ; these store everything that they need for any graph type
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;; startup and main loop ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to startup  ; structured this way in order to have a start page
  ca        ; I use the start page for a reminder to turn on the "go" button
  set running? false              ; true when data are being collected
  set waiting-to-start? false      ; used to turn on the display of the height on the vertical axis
  set waiting-to-analyze? false
  set waiting-to-setup?  false    ; used to force the user to press setup before running.   
  draw-first-page
  set starting? true
  reset-ticks
end

to go                           ; this is the main rountine repeatedly called at a high rate
  if starting? [
    ask drawing-dots [die]      ; gets rid of the startup message
    initialize                  ; initializes all the globals, creates needed turtles
    set starting? false
    reset-timer]                ; for research: reset timer to record when each run is made
  every dt [
    if running? [collect-data]  ; makes a measurement with the motion detector
    if not running? [
      if waiting-to-start? [
        show-height]            ; read the motion detctor and draw a dot on the vertical axis corresponding to the measurement
      act-on-changes ]           ; supports the duration slider but only if not running
    tick]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;  Mode cycling routines ;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The following four routines implement a cycle of run->stop->analyze->setup for each step of the game. 
; Uses four logicals
;   running?                initial value: F
;   waiting-to-start?       initial value: T
;   waiting-to-analyze?     initial value: F
;   waiting-to-setup?       initial value: F

to start                                        ; handles the start button--starts data collection
  ifelse waiting-to-start? and not running?     ; do something only if waiting-to-start? is true
    [set waiting-to-start? false                ; you get here only once each collection cycle
      set running? true 
      set points []]                        ; initialize the run-points list
    [report-wrong-button]
end

to handle-run-end                              ; called when running and (time > max-time)
  set running? false                           ; this does nothing but stop data collection
  set waiting-to-analyze? true                 ; and start waiting for the user to press the 'analyze data' or 'abort' buttons
  clear-output 
  pretty-print "Run completed!"
  if connected? [let x sensor:port -1 ]        ; turns off the motion detector 
  pretty-print "Press 'Analyze Data' to find out your new score."
end

to analyze-data                                 ; handles the 'analyze data' button
  ifelse waiting-to-analyze?  
    [set waiting-to-analyze? false              ; you get here only once per cycle
      set waiting-to-setup? true                ; start waiting for the user to press the 'setup' button
      update-score                              ; show the results of the last run   
      save-research-data                        ; save data relating to the just-completed run
      pretty-print "Press 'Setup New Run' to see your next challenge." ]
    [report-wrong-button]   
 
end

to setup-new-run                                ; handles the 'setup new run' button
  ifelse waiting-to-setup?                      ; do something only if waiting for this button
    [set waiting-to-setup? false
      set waiting-to-start? true                ; allows the go routine to show the height on the vertical axis
      create-new-challenge                      ; advances run counter, determines level and step, draws road
      pretty-print "Press 'Start' to begin."]
    [report-wrong-button] 
end

to abort
  ifelse running? or waiting-to-analyze? 
    [set running? false
      set waiting-to-start? true
      set waiting-to-analyze? false
      draw-grid
      draw-road 
      set time 0 
      set current-score 0
      set aborts lput (list timer points) aborts  ; save information about this abort
      set points []   ; clear the list of points
      clear-output
      pretty-print "You can start over now. Just press the 'Start' button."]
    [report-wrong-button]  
end

to report-wrong-button
  if waiting-to-start? [pretty-print "Now press the 'Start' button"]
  if running? [pretty-print "The only active key right now is 'Abort.'"]
  if waiting-to-analyze? [pretty-print "Now press the 'Analyze Data' button."]
  if waiting-to-setup? [pretty-print "Now you need to set up the next run. Press the 'Setup Next Run' button."]
  set wrong-button-count wrong-button-count + 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;  routines that support user actions ;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to collect-data                  ; reads the motion detector, graphs a point, checks for end of run
  let height 1
  if connected? [set height sensor:port 5]
  place-point time height graph-color   ; add a point at (time, height)
  set points lput (list (precision time 2) (precision height 3)) points
  set current-score current-score + evaluate time height
  set time time + dt
  if time > duration [handle-run-end]     ; stop
end

to act-on-changes
  if old-duration != duration [  ; the user has changed the duration slider
    set old-duration duration    ; 
    set grid-xmax duration
    rescale-grid                 ; creates a new grid but keeps road and drawing
    draw-road ]
end

to save-research-data            ; collects research data at the end of each completed run, when the user presses 'analyze-data'
    ; appends latest run data to data already on disk, if any, in a file called research-data
    ; the file contains only one object, a very long string which contains a structured list
    ; each item in the list provides all the data for a run, so the length research-data is the number of runs. 
    ; each run item consist of a list containing state, points, and aborts
    ; state is a list of variables that define the state of the game: timer-offset, total-score, level, step, messages-shown, and wrong-button-count
    ; points is a list of the (time, hight) pairs for the latest complete run
    ; aborts is a list of information about all aborted runs. It is a list, each item of which reports on an aborted run.
    ; each abort item consists of a list containing timer, level, step, and points (itself a list of time,height pairs), computed in the routine 'abort.'
    ; first collect the data for this run into a single list
    set state (list (timer + timer-offset)  total-score current-score level step messages-shown wrong-button-count)
    let run-data (list state points aborts)
    ; now read in prior data, append run-data, and save
    let prior []
    if file-exists? file-name [
      file-open file-name
      set prior file-read 
      file-close
      file-delete file-name ]
    set data lput run-data prior
    file-open file-name
    file-print (word data)
    file-close
    set points []  ; empty points (the list of time,height pairs)
    set aborts []  ; empty the list of aborts
end

to restore-state   ; reads the research data, gets the latest value of state, sets these values, sets the modal logicals, and recreates the last view
  if not file-exists? file-name [stop]
  file-open file-name  ; read all the data into the variable 'data'
  set data file-read 
  file-close  
  let prior last data   
  set state first prior     ; state now contains the state of the system the last time 'analyze data' was pressed
  ; state contains: the timer, total-score, level, step, messages-shown, and wrong-button-count
  set points item 1 prior   ; points now contain all the x,y values of the last full run
  reset-timer               ; the total time since the start of the game is timer + timer-offset
  ; lots more needed. 
  ; note: startup erases the file!! That will have to get smarter. 
end
  

    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;  Game routines ;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
to create-new-challenge       ; resets time (x-axis), clears the screen and output, advances run-number, 
  ; sets new level and step based on score, sets function, max-score, road-width, draws road, displays instructions
  set time 0
  ask graph-dots [die] ask road-dots [die]
  clear-output
  set run-number run-number + 1 ; advance run-number counter (run-number is initialized at -1)
  ifelse run-number = 0 ; the setup is unique for run zero. 
    [set level 1 set step 1]    ; always start at level 1 and step 1. 
    [get-next-step ]            ; changes the step and level depending on the just-computed score
  setup-game-variables          ; sets up the variables and instructions for this step and level.
  ; draw a grid that goes from 0 < time < duration (set by the slider) and .3 m < height < 1.5 m
;  set grid-xmin 0 set grid-xmax duration
;  set grid-ymin .3 set grid-ymax 1.5
  draw-grid      ; draws the graphing grid
  draw-road      ; shows the target road for this level and step
  set current-score 0
  pretty-print instructions
  tick
end
  
to get-next-step    ; determines whether the student stays at this step, goes up, or goes down
                    ; carries over to the next or previous level  
                    ; depends on current-score and max-score  
     
   let upper-break 2 * max-score / 3  ; the minimum score to advance
   let lower-break max-score / 3  ; the minimum score to stay at this step

   if current-score > upper-break [
     clear-output
     pretty-print "Congratulations! You advance a step."
     pretty-print "Now the road gets narrower. Good luck."
     set step step + 1
     if step > n-steps [
       clear-output
       pretty-print "Congratulations! You advance to a new level!!"
       ifelse level < max-level
         [set step 1
          set level level + 1 ]
         [ set step 1
           clear-output 
           pretty-print "Incredible!! You have reached the highest step at the highest level. You are a winner." 
           pretty-print "See if you can earn even more points at this level."
           ]]      ; if the student is on the last level, keep at the highest few steps. 
     stop]  ; 
   if current-score > lower-break [
     clear-output
     pretty-print (word "Based on your score, you should try a similar problem.")]
   
   if current-score <  lower-break [
     clear-output
     let k ""
     let m (word "Not so good. ")
     if step > 1 or level > 1 [set k "Try an easier problem."]
     set step step - 1 
     if step < 1 [ 
       set step 1   ; don't go below setp 1 and don't go to a lower level
       set k "Try again."]
     pretty-print word m k]
end

to setup-game-variables ; setup the game for the current level.
  let amax 0 let amin 0 let bmax 0 let bmin 0   ; declare some local variables
  let cmax 0 let cmin 0 let dmax 0 let dmin 0   ; the min and max valuse of a, b, c, and d, used in function. 
  ; a is random with a smooth probability between amin and amax
  ; b, c, and d are biased random that are more likely to return values near the min and max, and never return a middle value.
  if level = 1 [
    set max-score  100         ; the maximum score for one run that is possible for this level
    set n-steps  2
    set graph-type 1           ; straight line
    set amax 1.5 set amin .3   ; height of line
    set target-width-max .3    ; the maximum road width for step 1 in meters
    set target-width-min .1]   ; the road width for the highest step in this level]    
    
  if level = 2 [               ; a sloping line
    set max-score  150         ; the maximum score for one run that is possible for this level
    set n-steps  3   
    set graph-type 2           ; sloping line
    ifelse random 2 = 0        ; toss dice
      [ set amax .7 set amin .25      ; starting height for sloping up
        set bmax .8 set bmin .4 ]    ; slope up
      [ set amax 1.4 set amin .7     ; starting height for sloping down
        set bmax -.4 set bmin -0.8]  ; slope down
    set target-width-max .4    ; the maximum road width for step 1 in meters
    set target-width-min .15 ] ; the road width for the highest step in this level
 
  if level = 3 [               ; a flat line followed by a sloping one
    set max-score  180         ; the maximum score for one run that is possible for this level
    set n-steps  3
    set graph-type 3           ; flat followed by slope
    set amax 1 set amin .4     ; flat section height
    set bmax .5 set bmin .15   ; breakpoint value of x
    set cmax 1  set cmin -1   ; slope
    set target-width-max .3    ; the maximum road width for step 1 in meters
    set target-width-min .1]   ; the road width for the highest step in this level
  
  if level = 4 [
    set max-score  200         ; the maximum score for one run that is possible for this level
    set n-steps  3
    set graph-type 4           ; plateau
    set amax .4 set amin .1    ; left edge of plateau
    set bmax .75 set bmin .35  ; right edge of plateau
    set cmax 1.2  set cmin .3  ; bottom of plateau
    set dmax 1.3 set dmin .4   ; top of plateau
    set target-width-max .35   ; the maximum road width for step 1 in meters
    set target-width-min .15]   ; the road width for the highest step in this level]  
  
  if level = 5 [               ; sawtooth
    set max-score  350         ; the maximum score for one run that is possible for this level
    set n-steps  4
    set graph-type 6           ; sawtooth function
    set amax .8 set amin .6    ; centerline
    set bmax .4 set bmin .2    ; amplitide
    set cmax .7  set cmin .4    ; distance to first peak (fraction of period)
    set dmax .9 set dmin .3    ; period
    set target-width-max .45    ; the maximum road width for step 1 in meters
    set target-width-min .3]  ; the road width for the highest step in this level]         
  
  if level = 6 [               ; straight-curve-straight
    set max-score  300         ; the maximum score for one run that is possible for this level
    set n-steps  4
    set graph-type 5           ; straight-curve-straight
    set bmax .4 set bmin .2    ; x breakpoint between straight and quadratic
    ifelse random 2 = 0        ; throw the dice
      [set amax .4 set amin .3      ; curving up option: starting value
         set cmax 1.3  set cmin .6  ; final level y-value
         set dmax 4 set dmin 2 ]    ; curvature
      [set amax 1.4 set amin 1      ; curving down option: starting value
         set cmax .6  set cmin .3  ; final level y-value
         set dmax -2 set dmin -4 ]    ; curvature   
    set target-width-max .3    ; the maximum road width for step 1 in meters
    set target-width-min .1]  ; the road width for the highest step in this level]         
  
  if level = 7 [               ; oscilation
    set max-score  400         ; the maximum score for one run that is possible for this level
    set n-steps  4
    set graph-type 7           ; sine function
    set amax .8 set amin .6    ; centerline
    set bmax .4 set bmin .2    ; amplitide
    set cmax 2.5  set cmin .5    ; cycles shown
    set dmax 0 set dmin 360    ; phase shift
    set target-width-max .4    ; the maximum road width for step 1 in meters
    set target-width-min .2]  ; the road width for the highest step in this level]         

   ; Now set the width of the road for each step--decreasing from target-width-max to target-width-min
   set target-width target-width-max + (target-width-min - target-width-max ) * (step - 1) / (n-steps - 1)
   ; also sets params
   set param-a random-between amin amax         ; equally probable between these 
   set param-b biased-random-between bmin bmax  ; biased toward bmin and bmax
   set param-c biased-random-between cmin cmax
   set param-d biased-random-between dmin dmax  
end

to display-help-message 
  ; generates context-sensitive hints
  ; context is generated by step, level, and messages-shown, a list of the number of messages shown at level (item + 1)
  ; number-shown-already is the number of messages already shown to the user at this level. Stored in the messages-shown list. 
  let i level - 1
  let number-shown-already item i messages-shown
  let new 1 + item i messages-shown
  set messages-shown replace-item i messages-shown new 
  let m "Ask your teacher for help." ; the default message
  if level = 1  [
    set number-shown-already number-shown-already mod 7  ; insures that the messages cycle while the count remains valid
    if number-shown-already = 0 [
      set m "Note the red dot on the vertical axis. Move your hand above the motion detector and watch the red dot."]
    if number-shown-already = 1 [
      set m "Before starting, move the red dot to the center of the road."]
    if number-shown-already = 2 [
      set m "After starting, try to keep the red line in the center of the yellow road."]    
    if number-shown-already = 3 [
      set m "Keep your hand directly above the motion detector and be sure that there is nothing else above it."]    
    if number-shown-already = 4 [
      set m "If the red line disappears, you probably are not directly above the motion detector."]  
    if number-shown-already = 5 [
      set m "If you mess up, press the 'Abort' button to try again." ]
    if number-shown-already = 6 [
      set m "If the motion detector will not record long distances, look for a chair or table edge that might be reflecting the ultrasonic pulse back to the detector." ]    
    ]
    
  if level = 2 [
    set number-shown-already number-shown-already mod 4
    if number-shown-already = 0 [    
      set m "At this level, the road slopes so you have to move your hand to stay in the center." ]    
    if number-shown-already = 1 [
      set m "Hint: If the road slopes up, you have to move your hand up, too. If it slopes down, move your hand down."]    
    if number-shown-already = 2 [
      set m "Hint: The steeper the line, the faster you have to move your hand."]    
    if number-shown-already = 3 [
      set m "Don't forget, you can always abort a bad run. There is no penalty."]]
    
  if level = 3 [
    set number-shown-already number-shown-already mod 4
    if number-shown-already = 0 [    
      set m "At this level, the road is flat at first and then slopes. Watch carefully." ]  
    if number-shown-already = 1 [    
      set m "Each level is harder, but lets you earn higher scores. " ] 
    if number-shown-already = 2 [    
      set m "Hint: try changing the 'Duration' slider. Shorter durations are harder, but let you get scores faster." ] 
    if number-shown-already = 3 [    
      set m "If you increase the duration, it is easier to get high scores." ]]
  
  if level = 4 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "At this level, the road consists of three straight segments selected at random." ]  
    if number-shown-already = 1 [    
      set m "Hint: anticipate the places where the slope changes." ] 
    if number-shown-already = 2 [    
      set m "The steeper the road, the faster you have to move." ]]    

   if level = 5 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "At this level, the road consists of three straight segments selected at random." ]  
    if number-shown-already = 1 [    
      set m "Hint: Increase the duration--this slows things down and makes it easier to earn high scores." ] 
    if number-shown-already = 2 [    
      set m "The steeper the road, the faster you have to move." ]]  
     
  if level = 6 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "This is the first time you have seen a road that curves. Think what movement that requires." ]  
    if number-shown-already = 1 [    
      set m "Hint: you will have to speed up steadily as the curve increases its slope." ] 
    if number-shown-already = 2 [    
      set m "If the curve slopes down, you will have to move closer to the detector, speeding up as you get closer." ]]    

  if level = 7 [
    set number-shown-already number-shown-already mod 3
    if number-shown-already = 0 [    
      set m "At this level, the road goes up and down smoothly like a wave." ]  
    if number-shown-already = 1 [    
      set m "Hint: because the road steepness is always changing, you have to always change your velocity smoothly." ] 
    if number-shown-already = 2 [    
      set m "Where is the road steepest? This is where you have to move fastest." ]]     
    
  pretty-print m
  ; update the messages-shown list
  set number-of-hints reduce + messages-shown
end

to update-score ; called once when 'analyze' button is pressed.
  set current-score round current-score 
  set total-score round (total-score + current-score)
  clear-output
  if current-score > max-score [set current-score max-score]
  if current-score = 0 [
    pretty-print "Sorry, you didn't earn any score."
    pretty-print "Try to move down the middle of the yellow road."]
  if current-score > 0 [
    pretty-print (word "You scored " current-score " points out of a possible " max-score ".")
    let a ""
    if max-score - current-score < 5 [set a "That's a very high score. Way to go!!"]
    if max-score - current-score < 1 [set a "That is perfect. You got the highest possible score. Excellent!!"]
    if not empty? a [pretty-print a]
    pretty-print "This has been added to your total score."]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;; Road drawing routines ;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to draw-road     ; draws a road type graph-type, with parameters a, b, c, d
  ; the road fits between 0 and grid-xmax on the x-axis and has a width target-width
  let dz .0025 let z dz ; make lots of points for 0 <= z <= 1
  let who-upper 0
  while [z <= 1][                       ; repeat for 101 road segments
    let on-screen? true                 ; define a local flag
    let t z * grid-xmax                 ; the current t value corresponding to z
    let u mx * t + bx                   ; convert to screen coordinate
    let y function z                    ; the center of the road
    let v my * y + by                   ; convert center to screen coord
    let y-upper .5 * target-width + y   ; this is the upper road edge in meters
    let v-upper my * y-upper + by       ; convert to screen coordinate
    let y-lower y-upper - target-width  ; the lower road edge in meters
    let v-lower my * y-lower + by       ; convert to screen coord
    if v-upper > wind-vmax [            ; if the upper is off screen
      set v-upper wind-vmax             ; set the upper to screen max
      if v-lower > wind-vmax [set on-screen? false]]  ; if the lower is also off the top, set flag to not draw this segments
    if v-lower < wind-vmin [
      set v-lower wind-vmin
      if v-upper < wind-vmin [set on-screen? false]]
    if on-screen? [      ; if any part of the road is on-screen, draw a line from upper to lower edges of road
      create-road-dots 1 [           ; the centerline
        set shape "dot" set size 1          
        setxy u v
        set color grey]
      create-road-dots 1 [           ; the upper edge
        set shape "dot" set size 1          
        setxy u v-upper
        set who-upper who
        set color black]
      create-road-dots 1 [
        set shape "dot" set size 1   ; the lower edge
        setxy u v-lower
        set color black
        create-link-with road-dot who-upper [
          set color yellow
          set thickness 2 ]]]
    set z z + dz ]
end

to-report evaluate [t h] ; amount score is incremented each dt when the user places a point at y=h
  ; calculate the maximum possible score for this dt time interval
  ; scale with grid-xmax and dt so that a perfect score would be max-score
  ; there are duration / dt measurements, so the max-score-per-step = max-score * dt / duration
  let m max-score * dt / duration 
  ; find the middle of the road for this value of time, graph-type, and parameters
  let center function (t / duration)    ; the function argument goes from 0 to 1 and returns height of the road center
  let upper center + .5 * target-width  ; the upper bound
  let lower upper - target-width        ; the lower bound
  if h > upper or h < lower [report 0]  ; if h is outside the road, report zero
  report m * .5 * (1 + cos (360 * abs (h - center) / target-width)) ; a cos function that is zero at the edges and m at the center
end
    
to-report function [x]  ; x runs from 0 to 1. The reported value is the distance in meters.
  let a param-a let b param-b let c param-c let d param-d ; these are set in create-new-challenge
  if graph-type = 1 [        ; the simplest: level lines at a
    report a ]
    
  if graph-type = 2 [        ; gentle slopes. Starts at a and slopes up or down depending on param-b
    let y a  + b * x       ; keep value between .4 and 1.5
    if y > 1.4 [set y 1.4]
    if y < .4 [set y .4]
    report y ]

  if graph-type = 3 [        ; flat followed by slope. initial value is a. at b is slopes according to c
    let y 0 
    ifelse x < b 
      [set y a ]
      [set y a + c * (x - b)]
    if y > 1.5 [set y 1.5]
    if y < .25 [set y .25]
    report y]
    
 if graph-type = 4 [        ; this is a plateau between a and b that starts with y=c and plateaus at y=d
    if x < a [report c + (d - c) * x / a ]
    if x < b [report d ]
    report d + (c - d) * (x - b) / (1 - b)]
  
  if graph-type = 5 [              ; straight-curve-straight
    if x < b [report a ]           ; the inital straight segment
    let y a + d * (x - b ) ^ 2     ; a qudratic starting at b
    if d > 0 and y > c [report c]  ;  if the quadratic is rising and exceeds c, report c, making another straight section
    if d < 0 and y < c [report c]  ; if the quadratic is falling and goes below c, report c
    report y ]                     ; otherwise report the quadratic
    
  if graph-type = 6  [             ; sawtooth
    let z x mod d                  ; repeats every d units
    let z0 c * d                   ; the top of the sawtooth
    if z <= z0  [                  ; on the rise from (0, a-b) to (z0, a+b)
      report (a - b) + 2 * b * z / z0 ]
    if z > z0 [                    ; falling from  (z0, a+b) to (d, a-b)
      report a + b - 2 * b * (z - z0) / (d - z0)]]
  
  if graph-type = 7 [        ; Oscillations 
    ; vertical center is a, amplitude is b, number of cycles is c, phase is d
    report a + b * sin (d + (360 * c * x)) ]
  
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
;  ask graph-dots [die]
;  ask road-dots [die]
  draw-verticals   ; draws the vertical lines and the x-axis
  draw-horizontals ; draws the horizontal lines and the y-axis
end

to draw-verticals ; x-axis
  let xTarget (grid-umax - grid-umin ) * patch-size / grid-separation       ;  sets the target number of tics based on the size of the graphing area
                                                      ; allocates about grid-separation pixels per tic
  let a ticMarks grid-xMin grid-xMax xTarget        ; a now contains graph-xmin, graph-xmax, and n-xtics 
  set grid-xmin first a set grid-xmax item 1 a
  ; compute the transformation coeficients in u=mx+b
  set mx (grid-umax - grid-umin) / (grid-xmax - grid-xmin)
  set bx grid-umin - mx * grid-xmin
  let n-xtics last a
  let dxx (grid-xmax - grid-xmin) / (n-xtics - 1)
  let x grid-xmin
  repeat n-xtics [   ; draw and label the verticals one at a time
    let w 0 
    let u mx * x + bx
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
    setxy u grid-vmin - 12
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
  set my (grid-vmax - grid-vmin) / (grid-ymax - grid-ymin)
  set by grid-vmin - my * grid-ymin
  let n-ytics last a
  let dyy (grid-ymax - grid-ymin) / (n-ytics - 1)
  let y grid-ymin
  repeat n-ytics [   ; draw and label the horizontals one at a time
    let w 0 
    let v my * y + by
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
    set label grid-ylabel
    set label-color grid-label-color
    let u grid-umin + 1.5 * length grid-ylabel
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

to place-point [x y c]   ; places the point x,y on the grid as a dot of color c
  let u mx * x + bx
  let v my * y + by
  create-graph-dots 1 [ht
    set x-val x set y-val y 
    set color c
    set size 4 set shape "dot"
    if in-grid? u v [ st
      setxy u v ]]
end

to show-height 
  let y 1
  if connected? [set y sensor:port 5]
  let u grid-umin
  let v my * y + by
  ask graph-dots [die]
  create-graph-dots 1 [ht
    set x-val grid-xmin set y-val y 
    set color graph-color
    set size 6 set shape "dot"
    if in-grid? u v [st
      setxy u v ]]
end
    
to rescale-grid    ; redraws the grid and any points using the globals grid-xmin, grid-ymin,  etc....
  draw-grid
  ask graph-dots [
    let u mx * x-val + bx
    let v my * y-val + by
    ifelse in-grid? u v 
      [st setxy u v ]
      [ht]]    
  draw-road
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;  Initialization and support routines  ;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to initialize
  ; initialize control logic variabless
  set connected? true
  set dt .05 ; the time step--20 per second
  set time 0
  set old-mouse-down? false
  set output-width  65    ; characters in the output box, used with pretty-print
  set duration 10    ; start with the duration of the experiment set to 10 sec
  set old-duration duration   
  
  ; logicals that guide the user through the run-analyze-setup-run cycle
  set running? false              ; true when data are being collected
  set waiting-to-start? true      ; used to turn on the display of the height on the vertical axis
  set waiting-to-analyze? false
  set waiting-to-setup?  false    ; used to force the user to press setup before running.   

  ; Graph variables 
  ; define grid coordinates and labels
  ; define graphing window -- full width, top to middle
  set wind-umin min-pxcor set wind-umax max-pxcor
  set wind-vmax max-pycor set wind-vmin .3 * min-pycor
  ; now set the default grid values and draw the grid 
  set edge 8 set edge+ 18
  set grid-umin wind-umin + edge+ 
  set grid-umax wind-umax - edge
  set grid-vmin wind-vmin + edge+
  set grid-vmax wind-vmax - (edge + 4)    ; leave room for vertical axis lable. 
  set grid-separation 60    ; the approximate number of pixels per grid line
  set grid-xmin 0   set grid-xmax duration set grid-xlabel "Time (s)"
  set grid-ymin .2 set grid-ymax 1.5  set grid-ylabel "Distance (m)"
  set grid-color blue + 3 set grid-label-color blue - 1
  set graph-color red
  set tic-length 2.5   ; the distance a tic mark extends beyond the axis
  set line-width .5    ; the thin lines that make up the grid

  ; Game variables
  set max-level 7
  set total-score 0
  set run-number -1
  set messages-shown [0 0 0 0 0 0 0 ] ; initializes the number of help messages already shown to the student, by level
  create-new-challenge
  set aborts []          ; this will be a list of lists each describing one abort, giving time, leve, step
  
  ; Initial messages
  pretty-print "Remember: always leave the On/Off button on. When it is on, it is black."
  output-print ""
  pretty-print "Set the motion detector on the ground."
  pretty-print "Move your hand (or a book or something else) above the motion detector. Insure that nothing is above the detecor."
  pretty-print "Your goal is to use the motion detector to draw a clean, continuous line down the middle of the yellow road."
  
  reset-ticks
  ; turn on the motion detector
  wait .5
  carefully   ; test sensor and turn on
      [if connected? [ let f sensor:port 5 ]]
      [pretty-print "Problems with the motion detector."
       pretty-print "Check connections."
       pretty-print "Enter 'restart' in the command line and press 'return'." ] 
  ; now set up the data storage file
  set file-name "slalom-data"
  if file-exists? file-name [   ; if this file already exists, delete it. 
    file-open file-name
    file-close 
    file-delete file-name ]
  set timer-offset 0
end

to draw-first-page
  ask patches [set pcolor 9]
  create-drawing-dots 1 [
    set size .1
    setxy (.17 * min-pxcor) (.9 * max-pycor)
    set label "Press the On/Off button to continue." ]
  create-drawing-dots 1 [
    set size .1
    setxy .4 * min-pxcor .84 * max-pycor
    set label "   Leave it on all the time." ]
  ask drawing-dots [set label-color red]
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

to-report in-wind? [u v]  ; reports true if u,v is inside the graphing window
  report u >= wind-umin and u <= wind-umax and  v >= wind-vmin and v <= wind-vmax 
end
    
to-report in-grid? [u v] 
  report u >= grid-umin and u <= grid-umax and v >= grid-vmin and v <= grid-vmax
end

to-report random-between [a b]
  report a + random-float (b - a)
end

to-report biased-random-between [x0 x1]  ; this version just gives extreems, not the central half
  ; this is useful when you do want the result to be near x0 or x1 but not the middle
  let x random-between x0 x1
  let x2 (x0 + x1) / 2        ; the center
  let x3 (x0 + x2) / 2        ; the first quarter
  let x4 (x1 + x2) / 2        ; the third quarter
  if x > x2 and x < x4 [      ; this is the upper disallowed region
    set x x + x4 - x2 ]       ; move it from the third quarter to the forth
  if x > x3 and x < x2 [      ; the second quarter--the lower disallowed region
    set x x - (x3 - x0) ]     ; move it from the second quarter to the first
  report x
end
@#$#@#$#@
GRAPHICS-WINDOW
10
10
754
629
130
104
2.8134
1
12
1
1
1
0
0
0
1
-130
130
-104
104
0
0
0
ticks
30.0

BUTTON
11
10
113
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
111
560
208
594
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
14
529
130
562
Start
start
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
209
431
754
626
14

MONITOR
15
431
103
480
Total Score
Total-Score
0
1
12

MONITOR
100
431
210
480
Current Score
current-score
0
1
12

MONITOR
15
480
207
525
Level
(word Level  \" of \" max-level)
0
1
11

MONITOR
70
480
132
525
Step
(word Step \" of \" n-steps)
17
1
11

MONITOR
132
480
209
525
Max score
Max-score
17
1
11

BUTTON
15
561
112
594
Analyze data
analyze-data
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
14
593
207
626
Duration
Duration
5
60
10
5
1
sec
HORIZONTAL

BUTTON
129
529
208
562
Abort Run
Abort
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
661
10
753
43
Get a Hint
Display-help-message
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
