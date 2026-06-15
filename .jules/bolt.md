## 2024-06-25 - Use ListView.builder for lazy loading large lists
**Learning:** In Flutter, `ListView(children: [...])` evaluates and renders all widgets eagerly, leading to significant memory consumption and initial render times for large, recursive category trees like the library view.
**Action:** Always prefer `ListView.builder` over `ListView` for unbounded or large lists. Even if the underlying items have to be processed or flattened eagerly, passing them into `ListView.builder(itemCount: len, itemBuilder: ...)` defers rendering computation to only what is on-screen.
