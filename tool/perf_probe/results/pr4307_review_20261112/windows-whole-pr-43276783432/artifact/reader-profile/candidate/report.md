# דוח מדידות ביצועים

Commit: `6aa411d774f453331d6821dbb5a68f1c3b78bd78` · מצב: profile · מטמון: cold

הרצה שלמה: true · הצלחה: true

| תרחיש | מצב | n | p50 ms | p95 ms | p99 ms | build p95 ms | raster p95 ms | RSS peak MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| startup.first_content | passed | 4 | 579.315 | 649.288 | 649.288 | 54.166 | 152.043 | 323.219 |
| startup.window_useful | passed | 4 | 268.000 | 292.000 | 292.000 | — | — | — |
| book.short.open | passed | 16 | 98.491 | 107.164 | 107.164 | 25.571 | 3.797 | 896.984 |
| book.short.scroll | passed | 16 | 948.345 | 960.174 | 960.174 | 1.996 | 5.203 | 515.895 |
| book.short.jump_forward | passed | 16 | 64.619 | 80.365 | 80.365 | 38.480 | 2.396 | 537.215 |
| book.short.jump_backward | passed | 16 | 70.956 | 84.017 | 84.017 | 47.127 | 2.634 | 526.230 |
| book.short.warmup_complete | passed | 16 | 0.070 | 0.122 | 0.122 | — | — | 520.488 |
| book.short.steady_scroll | passed | 16 | 934.490 | 944.344 | 944.344 | 1.933 | 3.412 | 520.977 |
| book.short.close | passed | 16 | 360.559 | 368.328 | 368.328 | 2.588 | 2.514 | 529.551 |
| book.medium.open | passed | 16 | 107.168 | 131.253 | 131.253 | 26.371 | 3.955 | 530.152 |
| book.medium.scroll | passed | 16 | 1126.953 | 1263.264 | 1263.264 | 8.969 | 7.017 | 541.305 |
| book.medium.jump_forward | passed | 16 | 82.107 | 747.339 | 747.339 | 70.315 | 2.448 | 663.895 |
| book.medium.jump_backward | passed | 16 | 76.760 | 91.960 | 91.960 | 46.828 | 2.581 | 561.195 |
| book.medium.warmup_complete | passed | 16 | 1059.682 | 1136.733 | 1136.733 | 8.830 | 7.157 | 559.445 |
| book.medium.steady_scroll | passed | 16 | 934.222 | 950.709 | 950.709 | 1.961 | 5.183 | 553.711 |
| book.medium.close | passed | 16 | 357.435 | 368.537 | 368.537 | 3.043 | 2.411 | 547.613 |
| book.long.open | passed | 16 | 182.938 | 195.407 | 195.407 | 108.052 | 3.777 | 556.965 |
| book.long.scroll | passed | 16 | 964.392 | 1684.734 | 1684.734 | 11.011 | 3.664 | 960.020 |
| book.long.jump_forward | passed | 16 | 84.913 | 700.714 | 700.714 | 77.593 | 4.038 | 1090.254 |
| book.long.jump_backward | passed | 16 | 88.507 | 756.449 | 756.449 | 454.465 | 2.417 | 977.223 |
| book.long.warmup_complete | passed | 16 | 27536.347 | 27781.399 | 27781.399 | 9.319 | 6.544 | 893.637 |
| book.long.steady_scroll | passed | 16 | 934.416 | 956.662 | 956.662 | 1.886 | 7.147 | 966.914 |
| book.long.close | passed | 16 | 363.155 | 368.019 | 368.019 | 3.894 | 2.854 | 903.758 |
| windows.native_open_close | skipped | 0 | — | — | — | — | — | — |
| queues.depth | skipped | 0 | — | — | — | — | — | — |

| תרחיש | CPU ממוצע % ליבה | כיסוי CPU % | private peak MiB | heap אחרי p50 MiB | handles peak | תהליכים peak |
|---|---:|---:|---:|---:|---:|---:|
| startup.first_content | — | 0.000 | 290.035 | — | 617.000 | 1.000 |
| startup.window_useful | — | 0.000 | 221.930 | — | 553.000 | 1.000 |
| book.short.open | — | 0.000 | 691.910 | 74.301 | 611.000 | 1.000 |
| book.short.scroll | 28.884 | 51.803 | 383.711 | 81.933 | 616.000 | 1.000 |
| book.short.jump_forward | — | 0.000 | 408.066 | 74.934 | 618.000 | 1.000 |
| book.short.jump_backward | — | 0.000 | 371.242 | 73.770 | 605.000 | 1.000 |
| book.short.warmup_complete | — | 0.000 | — | 77.473 | — | — |
| book.short.steady_scroll | 26.119 | 42.733 | 377.539 | 77.961 | 612.000 | 1.000 |
| book.short.close | — | 0.000 | 384.941 | 74.150 | 607.000 | 1.000 |
| book.medium.open | — | 0.000 | 382.809 | 100.019 | 610.000 | 1.000 |
| book.medium.scroll | 84.230 | 54.027 | 408.176 | 87.425 | 607.000 | 1.000 |
| book.medium.jump_forward | 191.007 | 25.485 | 528.758 | 85.365 | 603.000 | 1.000 |
| book.medium.jump_backward | — | 0.000 | 401.723 | 84.496 | 602.000 | 1.000 |
| book.medium.warmup_complete | 93.082 | 51.711 | 412.531 | 99.208 | 606.000 | 1.000 |
| book.medium.steady_scroll | 36.745 | 44.575 | 421.289 | 100.686 | 606.000 | 1.000 |
| book.medium.close | — | 0.000 | 408.648 | 86.342 | 605.000 | 1.000 |
| book.long.open | — | 0.000 | 418.633 | 129.723 | 607.000 | 1.000 |
| book.long.scroll | 264.870 | 54.529 | 820.598 | 510.931 | 614.000 | 1.000 |
| book.long.jump_forward | 142.893 | 25.520 | 867.105 | 513.832 | 604.000 | 1.000 |
| book.long.jump_backward | 130.988 | 15.077 | 721.000 | 256.634 | 607.000 | 1.000 |
| book.long.warmup_complete | 103.694 | 98.002 | 752.738 | 456.191 | 612.000 | 1.000 |
| book.long.steady_scroll | 91.925 | 44.620 | 835.234 | 459.533 | 612.000 | 1.000 |
| book.long.close | — | 0.000 | 774.309 | 450.162 | 613.000 | 1.000 |
| windows.native_open_close | — | — | — | — | — | — |
| queues.depth | — | — | — | — | — | — |

אחוזונים: nearest-rank על דגימות מוצלחות בלבד, ללא warmup. מקף מציין מדד חסר. CPU: ‏100% = ליבה אחת; private memory הוא commit פרטי, ואינו אומדן לזיכרון native בלבד. דגימות גודל וזמן כיסוי CPU מפורטים ב-JSON.

## השוואה ל-baseline

| תרחיש | מצב | שינוי p50 | שינוי p95 | שינוי p99 |
|---|---|---:|---:|---:|---:|
| startup.first_content | compared | -3.238% | -18.579% | -18.579% |
| startup.window_useful | compared | 2.682% | -28.079% | -28.079% |
| book.short.open | compared | -1.616% | -1.511% | -1.511% |
| book.short.scroll | compared | 0.130% | 0.140% | 0.140% |
| book.short.jump_forward | compared | -1.696% | 3.139% | 3.139% |
| book.short.jump_backward | compared | -3.626% | 1.702% | 1.702% |
| book.short.warmup_complete | compared | 79.487% | 56.410% | 56.410% |
| book.short.steady_scroll | compared | -0.050% | -0.804% | -0.804% |
| book.short.close | compared | -0.323% | -0.073% | -0.073% |
| book.medium.open | compared | -6.755% | -15.960% | -15.960% |
| book.medium.scroll | compared | -10.263% | -8.027% | -8.027% |
| book.medium.jump_forward | compared | 1.389% | 1.868% | 1.868% |
| book.medium.jump_backward | compared | 19.949% | -3.646% | -3.646% |
| book.medium.warmup_complete | compared | -3.962% | -2.902% | -2.902% |
| book.medium.steady_scroll | compared | 0.136% | 0.372% | 0.372% |
| book.medium.close | compared | -0.706% | -0.046% | -0.046% |
| book.long.open | compared | -49.026% | -56.920% | -56.920% |
| book.long.scroll | compared | 1.218% | 28.062% | 28.062% |
| book.long.jump_forward | compared | -33.643% | -9.039% | -9.039% |
| book.long.jump_backward | compared | -24.744% | 6.129% | 6.129% |
| book.long.warmup_complete | compared | -10.781% | -21.707% | -21.707% |
| book.long.steady_scroll | compared | 0.195% | -2.354% | -2.354% |
| book.long.close | compared | -0.059% | -0.071% | -0.071% |
| windows.native_open_close | unavailable | — | — | — |
| queues.depth | unavailable | — | — | — |

שינוי חיובי הוא עלייה בזמן; אלה הבדלים תיאוריים, ללא קביעת מובהקות או סף CI.

## מגבלות המדידה

- p95/p99 עם מעט חזרות מתארים את המדגם בלבד; יש לבדוק את n
