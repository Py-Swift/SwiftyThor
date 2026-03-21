

# howto make pythons Widget / Canvas talk to SwiftyThor ...



```py
cdef class ThorInstruction
```

```py
cdef class ThorInstruction:

    cdef draw_on(tvg.Scene s): ...

    # properly func for adding / remove Scene/Shapes from Canvas (called by parent)
    # properly func for adding / remove Shapes/Scenes from Scene (called by parent)
```

```py
cdef class ThorInstructionGroup(ThorInstruction):

    cdef list instructions

    cdef tvg.Scene _scene

    cdef draw_on(tvg.Scene s):

        for instruction in self.instructions:
            (<ThorInstruction>)instruction.draw_on(self._scene) # ?..
```

```py
cdef class ThorCanvasBase: ...

    # like CanvasBase
    # InstructionGroup + add / remove functions
    # Uses tvg.Scene

cdef class ThorCanvas:

    cdef TCanvasScene _before_
    cdef TCanvasScene _after_

    cdef draw_on(tvg.Scene s):

        # draw order before
        for instruction in self._before_.instructions:
            instruction.draw_on(self._scene) # ?..
        # draw order after
        for instruction in self._after_.instructions:
            instruction.draw_on(self._scene) # ?..


    @property
    def before(self) -> TCanvasScene:
        return self._before_

    @property
    def after(self) -> TCanvasScene:
        return self._after_

```


```py

cdef class _TWidgetBase(EventDispatcher):

    ThorCanvas _c_

    @property
    def canvas(self) -> ThorCanvas:
        return self._c_

    cdef draw_on(tvg.Scene s):
        self._c_.draw_on(s)


```

```py

TWidgetBase = WidgetMetaclass('TWidgetBase', (_TWidgetBase, ), {})

class TWidget(TWidgetBase):
    ...

```



```py

cdef class TScreen

    cdef ThorCanvas _c_
    cdef tvg.Scene _s_

    @property
    def canvas(self) -> ThorCanvas:
        return self._c_

    cdef canvas_update(tvg.Canvas c):

        # update / redraw / reorder canvas children
        
        # update _c_
        self._c_.draw_on(self._s_)        


    cdef draw_on(tvg.Scene s):
        self._c_.draw_on(s)

# only one each window should be allowed
# and a more refined TabManager can be used as "sub screens / screenmanager
cdef class TScreenManager

    cdef TScreen _current
    cdef TScreen _last

    cdef bint transition_active
    # check transition_active

    @property
    def canvas(self) -> ThorCanvas:
        return self._c_

    cdef canvas_update(tvg.Canvas c):
        self._current.canvas_update(c)
        if self.transition_active:
            self._last.canvas_update(c)
```


(already exist in the side that tests the library)
```py
class WindowThor(WindowBase):
    def add_widget(self, widget, canvas=None):
        Logger.debug('WindowThor: add_widget %s (canvas=%s)', widget, canvas)
        #return super().add_widget(widget, canvas)

```

on Window launch kivy engine will call add_widget with the root widget
and this should i guess just be passed to Swift side as a struct
that contains a 

* void* obj
* void canvas_draw(void*, Canvas) (function pointer, passing obj and current Canvas) # not sure if needed or we start with Scene already
* void draw_on(void*, Scene) (function pointer, passing obj and current Canvas)
* bool draw_screen


on cython/python side we will use 
-> thorvg-cython

and ThorKivy/src/thorkivy/instructions
already got abit of the concept, but we dont need all the bloated stuff it has anymore
since update calls passes canvas / scene
and no need for viewport or fbo id or anything...