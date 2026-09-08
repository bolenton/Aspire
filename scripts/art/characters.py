"""Lantern's original storybook cast, with named joints for calm runtime animation."""
import math
from geometry import box, curve, ellipsoid, empty, lathe, material, mesh, tube


def explorer():
    coat = material('Explorer • woven ocean teal', (.025,.24,.27), .82)
    lining = material('Explorer • ivory shearling', (.89,.82,.63), .95)
    gold = material('Explorer • brushed brass', (.64,.37,.075), .3, .65)
    skin = material('Explorer • warm skin', (.56,.30,.17), .67)
    cheek = material('Explorer • rose cheeks', (.58,.21,.14), .75)
    hair = material('Explorer • chestnut hair', (.065,.025,.016), .7)
    leather = material('Explorer • saddle leather', (.17,.065,.025), .67)
    dark = material('Explorer • ink', (.009,.018,.027), .35)
    white = material('Explorer • eye whites', (.98,.94,.84), .32)
    iris = material('Explorer • hazel eyes', (.18,.28,.19), .25)
    scarf = material('Explorer • saffron knit', (.91,.46,.06), .85)
    glow = material('Explorer • honey lantern', (1,.58,.15), .25, emission=2)
    root = empty('Explorer')
    # A flared tailored coat with a defined waist, shoulder line and collar.
    body = empty('Torso', parent=root)
    lathe('Tailored coat', [(.69,.37,.24,0),(.73,.39,.26,0),(.9,.31,.22,0),
          (1.10,.28,.20,0),(1.34,.34,.22,0),(1.40,.25,.18,0)], coat, body)
    lathe('Cream hem', [(.68,.374,.245,0),(.73,.393,.267,0),(.77,.38,.255,0)], lining, body)
    curve('Front seam', [(0,.77,.26),(0,1.02,.218),(0,1.34,.226)], .012, gold, body)
    for h in (.88,1.06,1.23):
        ellipsoid('Brass coat button', (.062,h,.223), (.025,.025,.014), gold, body)
    for x in (-.21,.21):
        curve('Pocket welt', [(x-.065,.9,.229),(x,.885,.25),(x+.065,.9,.229)], .013, lining, body)
    # Arms pivot at the shoulders; each separate sleeve retains a rounded cuff and hand.
    for sign, side in ((-1,'L'),(1,'R')):
        arm = empty('Arm.'+side, (sign*.31,1.30,0), root)
        tube('Shaped sleeve', [(0,0,0),(sign*.07,-.12,.015),(sign*.13,-.32,.045),
                              (sign*.12,-.43,.09)], [.14,.145,.11,.095], coat, arm)
        ellipsoid('Ivory cuff', (sign*.12,-.43,.09), (.105,.07,.105), lining, arm)
        ellipsoid('Hand', (sign*.12,-.52,.11), (.087,.115,.075), skin, arm)
        ellipsoid('Thumb', (sign*.07,-.49,.16), (.035,.055,.038), skin, arm)
        leg = empty('Leg.'+side, (sign*.16,.74,0), root)
        tube('Trousers', [(0,.05,0),(0,-.22,.01),(0,-.56,.01)], [.116,.10,.083], dark, leg)
        box('Boot', (0,-.58,.055), (.25,.30,.38), leather, .10, leg)
        box('Boot sole', (0,-.69,.075), (.26,.055,.39), dark, .024, leg)
        for h in (-.45,-.53):
            curve('Boot stitching', [(-.07,h,.235),(0,h-.008,.249),(.07,h,.235)], .009, lining, leg)
    # Backpack gives the rear camera a readable, crafted hero silhouette.
    box('Canvas backpack', (0,1.12,-.27), (.48,.53,.24), scarf, .12, body)
    box('Backpack flap', (0,1.29,-.405), (.48,.21,.055), leather, .07, body)
    box('Backpack pocket', (0,.99,-.413), (.31,.19,.065), coat, .045, body)
    for x in (-.16,.16):
        curve('Shoulder strap', [(x,.83,-.35),(x,1.35,-.24),(x,1.39,.10),(x,1.02,.23)], .027, leather, body)
    box('Backpack buckle', (0,1.23,-.445), (.10,.11,.035), gold, .016, body)
    # Neck and head: broad readable face, individual iris / lids / brows and soft cheeks.
    ellipsoid('Neck', (0,1.45,0), (.115,.16,.11), skin, body)
    head = empty('Head', (0,1.71,0), root)
    lathe('Face', [(-.27,.06,.08,.02),(-.24,.18,.17,.035),(-.13,.265,.235,.01),
          (.02,.285,.255,0),(.18,.26,.23,-.015),(.28,.18,.16,-.02),(.31,.02,.02,-.02)], skin, head)
    for sign in (-1,1):
        ellipsoid('Ear', (sign*.28,-.04,0), (.064,.092,.047), skin, head)
        ellipsoid('Rosy cheek', (sign*.174,-.10,.214), (.064,.037,.013), cheek, head)
        eye = empty('Eye.'+('L' if sign<0 else 'R'), (sign*.12,.015,.219), head)
        ellipsoid('Eye white', (0,0,0), (.079,.094,.038), white, eye)
        ellipsoid('Iris', (0,-.006,.035), (.046,.061,.012), iris, eye)
        ellipsoid('Pupil', (0,-.008,.046), (.024,.041,.008), dark, eye)
        ellipsoid('Eye sparkle', (-.012,.019,.055), (.014,.018,.007), white, eye)
        curve('Upper lid', [(sign*.12-.073,.043,.233),(sign*.12,.098,.247),(sign*.12+.073,.043,.233)], .012, hair, head)
        curve('Expressive brow', [(sign*.12-.06,.132,.216),(sign*.12,.156,.23),(sign*.12+.06,.137,.219)], .018, hair, head)
    ellipsoid('Nose', (0,-.062,.264), (.044,.048,.046), skin, head)
    curve('Quiet smile', [(-.064,-.174,.192),(0,-.186,.209),(.064,-.174,.192)], .009, leather, head)
    # Sculpted fringe strands and two braids, not a featureless helmet.
    ellipsoid('Hair back', (0,.06,-.105), (.293,.277,.206), hair, head)
    for i in range(9):
        x = -.23+i*.056
        curve('Swept fringe', [(x*.55,.276,.07),(x,.23,.191),(x+.04,.145+.07*abs(x),.214)], .039, hair, head)
    for sign in (-1,1):
        for i in range(8):
            x = sign*(.26+.03*math.sin(i*2.2))
            ellipsoid('Braided hair', (x,-.10-i*.068,-.084), (.052,.067,.057), hair, head, 20)
        ellipsoid('Braid ribbon', (sign*.275,-.57,-.084), (.074,.028,.067), scarf, head)
    # Soft cap with a stitched band; head stays distinct from the coat.
    ellipsoid('Explorer cap', (0,.287,-.025), (.34,.12,.28), scarf, head)
    lathe('Cap leather band', [(.239,.29,.249,-.01),(.264,.295,.254,-.01),(.28,.29,.25,-.01)], leather, head)
    ellipsoid('Cap button', (.08,.403,-.04), (.046,.024,.046), gold, head)
    # Generous scarf collar and gently curved front tail.
    lathe('Knitted scarf collar', [(1.36,.20,.17,.01),(1.42,.22,.18,.01),(1.46,.18,.15,.01)], scarf, body)
    tube('Scarf tail', [(-.16,1.39,.18),(-.20,1.20,.265),(-.17,1.02,.30)], [.066,.072,.067], scarf, body, 8)
    # A recognisable little lantern fixed to the pack, with a cage, handle and warm core.
    lantern((.34,.91,-.20), .24, gold, glow, root)
    return root


def lantern(position, scale, metal, glow, parent=None):
    p = empty('Lantern', position, parent)
    ellipsoid('Warm glass', (0,scale*.4,0), (scale*.31,scale*.43,scale*.31), glow, p)
    for h in (0,scale*.81):
        box('Lantern rim', (0,h,0), (scale*.8,scale*.12,scale*.8), metal, scale*.07, p)
    for x,z in ((-1,-1),(-1,1),(1,-1),(1,1)):
        tube('Lantern cage', [(x*scale*.32,0,z*scale*.32),(x*scale*.32,scale*.80,z*scale*.32)], [scale*.04]*2, metal, p, 8)
    curve('Lantern handle', [(-scale*.26,scale*.87,0),(-scale*.26,scale*1.15,0),(0,scale*1.27,0),(scale*.26,scale*1.15,0),(scale*.26,scale*.87,0)], scale*.036, metal, p)
    return p


def fox():
    orange = material('Ember • copper fur', (.71,.205,.046), .83)
    light = material('Ember • golden highlights', (.91,.35,.075), .85)
    cream = material('Ember • warm ivory', (.94,.85,.66), .94)
    dark = material('Ember • charcoal paws', (.042,.028,.028), .8)
    pink = material('Ember • velvet inner ears', (.43,.12,.12), .88)
    nose = material('Ember • glossy nose', (.025,.027,.032), .25)
    iris = material('Ember • amber eyes', (.36,.19,.035), .32)
    white = material('Ember • eye glint', (1,.98,.89), .2)
    scarf = material('Ember • blue woven scarf', (.025,.27,.32), .85)
    brass = material('Ember • bell', (.70,.41,.07), .25, .65)
    root = empty('Ember')
    torso = empty('Torso', parent=root)
    ellipsoid('Chest and haunches', (0,.66,-.13), (.31,.40,.54), orange, torso)
    ellipsoid('Ivory chest', (0,.69,.367), (.23,.30,.15), cream, torso)
    for sign in (-1,1):
        for z,label in ((.20,'Front'),(-.49,'Back')):
            leg = empty('Leg.'+label+('.L' if sign<0 else '.R'), (sign*.215,.59,z), root)
            tube('Tapered leg', [(0,0,0),(0,-.19,.01),(0,-.40,.015)], [.12,.085,.065], orange, leg)
            tube('Dark stockings', [(0,-.30,.012),(0,-.45,.025)], [.072,.063], dark, leg)
            ellipsoid('Paw', (0,-.49,.071), (.094,.068,.15), dark, leg)
            for toe in (-.03,.03):
                curve('Paw seam', [(toe,-.515,.199),(toe,-.48,.20)], .005, nose, leg)
    head = empty('Head', (0,1.03,.30), root)
    ellipsoid('Fox head', (0,.08,0), (.375,.32,.30), orange, head)
    # Sculpted outer ear surfaces with inset velvety inner triangles.
    for sign in (-1,1):
        verts=[(sign*.10,.20,.055),(sign*.35,.17,.015),(sign*.37,.60,-.02),
               (sign*.12,.19,-.15),(sign*.35,.17,-.15),(sign*.35,.57,-.10)]
        pivot=empty('Ear.'+('L' if sign<0 else 'R'),(sign*.24,.19,0),head)
        verts=[(x-sign*.24,y-.19,z) for x,y,z in verts]
        ear = mesh('Pointed ear', verts, [(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)], orange, pivot)
        bevel = ear.modifiers.new('Soft ear edges','BEVEL')
        bevel.width=.035
        bevel.segments=3
        mesh('Inner ear', [(sign*(-.07),.07,.061),(sign*.06,.04,.025),(sign*.106,.31,-.003)], [(0,1,2)], pink, pivot, False)
        ellipsoid('Cream cheek ruff', (sign*.23,-.055,.207), (.18,.14,.145), cream, head)
        for i in range(3):
            tube('Cheek fur tuft', [(sign*.29,-.02-i*.057,.04),(sign*(.45-i*.022),.04-i*.072,.014)], [.069,.002], cream, head, 8)
        eye = empty('Eye.'+('L' if sign<0 else 'R'), (sign*.164,.132,.245), head)
        ellipsoid('Eye dark rim', (0,0,0), (.094,.119,.04), dark, eye)
        ellipsoid('Eye ivory', (0,0,.019), (.081,.102,.024), white, eye)
        ellipsoid('Amber iris', (-sign*.006,-.008,.040), (.053,.073,.016), iris, eye)
        ellipsoid('Black pupil', (-sign*.008,-.005,.055), (.030,.053,.011), nose, eye)
        ellipsoid('Eye glint', (-.018,.025,.066), (.018,.023,.007), white, eye)
        curve('Friendly eyebrow', [(sign*.16-.075,.28,.198),(sign*.16,.30,.21),(sign*.16+.06,.266,.192)], .02, light, head)
    ellipsoid('Tapered muzzle', (0,-.056,.298), (.174,.11,.205), cream, head)
    ellipsoid('Heart shaped nose', (0,-.016,.486), (.072,.048,.034), nose, head)
    curve('Muzzle seam', [(0,-.05,.476),(0,-.095,.454)], .008, dark, head)
    jaw=empty('Jaw',(0,-.10,.29),head)
    ellipsoid('Ember lower jaw',(0,-.045,.09),(.125,.045,.14),cream,jaw)
    curve('Smile', [(-.10,-.10,.396),(0,-.13,.434),(.10,-.10,.396)], .007, dark, head)
    # Broad, swept tail uses a single continuous tapered mesh with an ivory tip.
    tail = empty('Tail', (0,.55,-.56), root)
    tube('Bushy copper tail', [(0,0,0),(.08,.12,-.27),(.23,.31,-.51),(.33,.56,-.62),(.35,.71,-.61)], [.13,.20,.24,.20,.15], orange, tail, 24)
    tube('Ivory tail tip', [(.35,.69,-.61),(.32,.83,-.58),(.23,.94,-.47),(.13,.96,-.39)], [.157,.12,.073,.002], cream, tail, 24)
    lathe('Ember scarf', [(.88,.273,.22,.22),(.95,.286,.22,.22),(.99,.27,.20,.23)], scarf, torso)
    tube('Scarf end', [(.20,.94,.30),(.28,.76,.38),(.31,.59,.36)], [.077,.08,.055], scarf, torso, 8)
    ellipsoid('Small brass bell', (0,.81,.383), (.063,.071,.059), brass, torso)
    curve('Bell slit', [(-.032,.795,.438),(0,.78,.445),(.032,.795,.438)], .006, nose, torso)
    return root


def acorn():
    amber=material('Acorn • golden shell',(.82,.43,.065),.28,.22)
    cap=material('Acorn • carved cup',(.24,.09,.025),.78)
    scale=material('Acorn • cup scales',(.36,.16,.047),.75)
    green=material('Acorn • little oak leaf',(.19,.39,.095),.78)
    root=empty('Song acorn')
    lathe('Polished acorn',[(.12,.015,.015,0),(.22,.19,.19,0),(.38,.30,.30,0),(.62,.34,.34,0),(.79,.30,.30,0),(.83,.08,.08,0)],amber,root)
    ellipsoid('Acorn cup',(0,.78,0),(.35,.17,.35),cap,root)
    for row in range(4):
        a=row*.31
        radius=.345*math.cos(a)
        for i in range(15):
            angle=i*math.tau/15+row*.2
            ellipsoid('Cup scale',(math.cos(angle)*radius,.78+math.sin(a)*.155,math.sin(angle)*radius),(.049,.047,.049),scale,root,16)
    curve('Curled acorn stem',[(0,.9,0),(.025,1.08,0),(.16,1.12,.015)],.044,cap,root)
    leaf=mesh('Oak leaf',[(.02,1.05,0),(-.17,1.24,.02),(-.38,1.29,0),(-.33,1.15,.02),(-.23,1.12,.055),(-.12,1.08,.02)],[(0,1,2,3,4,5)],green,root)
    curve('Oak leaf vein',[(.02,1.06,.01),(-.16,1.16,.034),(-.34,1.26,.015)],.008,amber,root)
    return root
