# LMS Course Tracker (Theme Component)

Frontend-Theme-Komponente für das [discourse-lms](https://github.com/oxscience/discourse-lms) Plugin. Zeigt Kurs-Header, Fortschrittsbalken, Lektions-Nummerierung und Completion-Badges auf LMS-aktivierten Kategorien an.

## Installation

Admin → Customize → Themes → Components → "Install" → "From a Git Repository":

```
https://github.com/oxscience/discourse-lms-theme
```

Danach die Komponente an das aktive Theme anhängen (Foundation, Horizon oder das jeweilige Eltern-Theme).

## Voraussetzungen

- Das [discourse-lms](https://github.com/oxscience/discourse-lms) Plugin muss installiert und aktiviert sein (`lms_enabled` Site Setting).
- Mindestens eine Kategorie mit aktivierter Kurs-Checkbox.

## Architektur-Hinweise

- Die Topic-List-Sortierung in Kurs-Kategorien läuft **server-seitig** im Plugin (`TopicQuery#apply_ordering`). Die Theme-Komponente fügt nur Badges und Nummerierung hinzu, verschiebt keine DOM-Rows.
- Layout-Shifts werden vermieden, indem der Progress-Bar sofort als leeres Skelett eingefügt und dann in-place aktualisiert wird.

## Lizenz

MIT
