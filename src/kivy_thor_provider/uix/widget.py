# widget.py — TWidget (pure Python, mirrors kivy.uix.widget)
#
# Pure Python so kivy is NOT required at wheel-build time.
import weakref

from kivy.event import EventDispatcher
from kivy.uix.widget import WidgetMetaclass
from kivy.properties import NumericProperty, ReferenceListProperty, StringProperty

from kivy_thor_provider.graphics.canvas import ThorCanvas


class _TWidgetBase(EventDispatcher):
    """ThorVG widget base: ThorCanvas + child list + Kivy EventDispatcher.

    Drawing machinery lives here; Kivy Properties and event dispatch are
    applied via WidgetMetaclass at the TWidgetBase / TWidget level.
    """

    def __init__(self, **kwargs):
        self._canvas     = ThorCanvas()
        self._children   = []
        self._parent_ref = None
        super().__init__(**kwargs)

    @property
    def canvas(self):
        """This widget's ThorCanvas (before / main / after layers)."""
        return self._canvas

    # ------------------------------------------------------------------
    # Child management
    # ------------------------------------------------------------------

    def add_widget(self, widget, index=None):
        if index is None:
            self._children.append(widget)
        else:
            self._children.insert(index, widget)
        if hasattr(widget, '_parent_ref'):
            widget._parent_ref = weakref.ref(self)

    def remove_widget(self, widget):
        self._children.remove(widget)
        if hasattr(widget, '_parent_ref'):
            widget._parent_ref = None

    @property
    def children(self):
        return list(self._children)

    @property
    def parent(self):
        ref = self._parent_ref
        return ref() if ref is not None else None

    # ------------------------------------------------------------------
    # Rendering — called once at attach_canvas time
    # ------------------------------------------------------------------

    def draw_on(self, scene):
        """Add this widget's canvas paints (and all children) into *scene*.

        Called once when the screen builds its persistent paint tree.
        After that, mutate paint handles directly — no redraw needed.
        """
        self._canvas.draw_on(scene)
        for child in self._children:
            child.draw_on(scene)


# Apply WidgetMetaclass to gain Kivy Property / event dispatch
TWidgetBase = WidgetMetaclass('TWidgetBase', (_TWidgetBase,), {})


class TWidget(TWidgetBase, metaclass=WidgetMetaclass):
    """Standard ThorVG widget with Kivy-style layout properties.

    Drop-in structural replacement for kivy.uix.widget.Widget using ThorVG
    for all drawing instead of OpenGL instructions.
    """
    x      = NumericProperty(0)
    y      = NumericProperty(0)
    width  = NumericProperty(100)
    height = NumericProperty(100)
    pos    = ReferenceListProperty(x, y)
    size   = ReferenceListProperty(width, height)
    id     = StringProperty('')
