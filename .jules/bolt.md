## 2024-04-26 - Adjusting ListView cacheExtent
**Learning:** Default cacheExtent for ListView in Flutter (250 pixels) might lead to stuttering scrolling experience, especially for lists with complex items. However, significantly large cacheExtent values like 3000 can cause initial memory bloat or OOM issues.
**Action:** Use a moderate value like 1000px to balance between memory usage and scroll smoothness.
