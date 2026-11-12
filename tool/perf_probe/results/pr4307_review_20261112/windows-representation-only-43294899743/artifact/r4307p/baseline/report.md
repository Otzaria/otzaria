# דוח מדידות ביצועים

Commit: `7c35746e2fa5709235bc360bc13b2384e569aafb` · מצב: profile · מטמון: cold

הרצה שלמה: true · הצלחה: true

| תרחיש | מצב | n | p50 ms | p95 ms | p99 ms | build p95 ms | raster p95 ms | RSS peak MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| startup.first_content | passed | 4 | 525.550 | 620.349 | 620.349 | 47.362 | 149.170 | 330.891 |
| startup.window_useful | passed | 4 | 248.000 | 327.000 | 327.000 | — | — | — |
| book.short.open | passed | 16 | 85.487 | 97.695 | 97.695 | 20.120 | 4.738 | 914.637 |
| book.short.scroll | passed | 16 | 937.278 | 1038.563 | 1038.563 | 6.255 | 5.538 | 524.309 |
| book.short.jump_forward | passed | 16 | 57.882 | 62.859 | 62.859 | 30.244 | 2.251 | 550.902 |
| book.short.jump_backward | passed | 16 | 53.310 | 74.824 | 74.824 | 37.692 | 2.062 | 542.727 |
| book.short.warmup_complete | passed | 16 | 0.029 | 3.210 | 3.210 | — | — | 527.090 |
| book.short.steady_scroll | passed | 16 | 931.558 | 940.024 | 940.024 | 1.735 | 4.401 | 527.820 |
| book.short.close | passed | 16 | 358.896 | 366.448 | 366.448 | 2.311 | 1.901 | 532.980 |
| book.medium.open | passed | 16 | 102.261 | 175.551 | 175.551 | 35.012 | 3.430 | 543.477 |
| book.medium.scroll | passed | 16 | 1135.857 | 1202.797 | 1202.797 | 11.506 | 5.193 | 548.746 |
| book.medium.jump_forward | passed | 16 | 66.477 | 83.996 | 83.996 | 34.292 | 2.158 | 570.582 |
| book.medium.jump_backward | passed | 16 | 52.525 | 76.302 | 76.302 | 41.404 | 5.342 | 544.035 |
| book.medium.warmup_complete | passed | 16 | 1116.097 | 1202.496 | 1202.496 | 7.180 | 2.472 | 545.152 |
| book.medium.steady_scroll | passed | 16 | 933.874 | 940.290 | 940.290 | 1.726 | 3.233 | 560.473 |
| book.medium.close | passed | 16 | 363.447 | 368.014 | 368.014 | 2.124 | 1.875 | 556.148 |
| book.long.open | passed | 16 | 300.876 | 325.527 | 325.527 | 87.448 | 5.650 | 656.945 |
| book.long.scroll | passed | 16 | 963.317 | 998.229 | 998.229 | 2.258 | 2.840 | 1000.117 |
| book.long.jump_forward | passed | 16 | 93.690 | 538.874 | 538.874 | 308.559 | 2.196 | 1036.148 |
| book.long.jump_backward | passed | 16 | 89.931 | 546.937 | 546.937 | 311.357 | 1.888 | 899.359 |
| book.long.warmup_complete | passed | 16 | 28820.181 | 31496.668 | 31496.668 | 7.099 | 2.376 | 947.133 |
| book.long.steady_scroll | passed | 16 | 933.243 | 969.440 | 969.440 | 1.641 | 5.510 | 992.063 |
| book.long.close | passed | 16 | 363.565 | 367.655 | 367.655 | 3.376 | 2.298 | 936.266 |
| windows.native_open_close | skipped | 0 | — | — | — | — | — | — |
| queues.depth | skipped | 0 | — | — | — | — | — | — |

| תרחיש | CPU ממוצע % ליבה | כיסוי CPU % | private peak MiB | heap אחרי p50 MiB | handles peak | תהליכים peak |
|---|---:|---:|---:|---:|---:|---:|
| startup.first_content | — | 0.000 | 303.473 | — | 622.000 | 1.000 |
| startup.window_useful | — | 0.000 | 202.828 | — | 548.000 | 1.000 |
| book.short.open | — | 0.000 | 781.883 | 73.967 | 613.000 | 1.000 |
| book.short.scroll | 24.762 | 52.877 | 388.141 | 77.161 | 615.000 | 1.000 |
| book.short.jump_forward | — | 0.000 | 412.336 | 75.220 | 612.000 | 1.000 |
| book.short.jump_backward | — | 0.000 | 376.680 | 73.879 | 612.000 | 1.000 |
| book.short.warmup_complete | — | 0.000 | — | 78.118 | — | — |
| book.short.steady_scroll | 24.284 | 44.017 | 385.148 | 75.838 | 616.000 | 1.000 |
| book.short.close | — | 0.000 | 398.590 | 74.861 | 614.000 | 1.000 |
| book.medium.open | — | 0.000 | 389.879 | 99.393 | 607.000 | 1.000 |
| book.medium.scroll | 117.829 | 53.620 | 402.590 | 90.919 | 611.000 | 1.000 |
| book.medium.jump_forward | — | 0.000 | 418.230 | 86.735 | 611.000 | 1.000 |
| book.medium.jump_backward | — | 0.000 | 406.684 | 85.343 | 607.000 | 1.000 |
| book.medium.warmup_complete | 74.006 | 58.139 | 406.047 | 94.900 | 611.000 | 1.000 |
| book.medium.steady_scroll | 27.385 | 53.460 | 425.527 | 95.527 | 611.000 | 1.000 |
| book.medium.close | — | 0.000 | 418.156 | 90.224 | 609.000 | 1.000 |
| book.long.open | — | 0.000 | 498.848 | 167.254 | 610.000 | 1.000 |
| book.long.scroll | 223.629 | 45.423 | 865.063 | 565.949 | 616.000 | 1.000 |
| book.long.jump_forward | — | 0.000 | 901.145 | 302.452 | 611.000 | 1.000 |
| book.long.jump_backward | — | 0.000 | 724.988 | 301.935 | 610.000 | 1.000 |
| book.long.warmup_complete | 121.149 | 98.174 | 790.668 | 463.835 | 615.000 | 1.000 |
| book.long.steady_scroll | 42.337 | 50.043 | 840.254 | 469.301 | 609.000 | 1.000 |
| book.long.close | — | 0.000 | 773.332 | 464.422 | 613.000 | 1.000 |
| windows.native_open_close | — | — | — | — | — | — |
| queues.depth | — | — | — | — | — | — |

אחוזונים: nearest-rank על דגימות מוצלחות בלבד, ללא warmup. מקף מציין מדד חסר. CPU: ‏100% = ליבה אחת; private memory הוא commit פרטי, ואינו אומדן לזיכרון native בלבד. דגימות גודל וזמן כיסוי CPU מפורטים ב-JSON.

## מגבלות המדידה

- p95/p99 עם מעט חזרות מתארים את המדגם בלבד; יש לבדוק את n
