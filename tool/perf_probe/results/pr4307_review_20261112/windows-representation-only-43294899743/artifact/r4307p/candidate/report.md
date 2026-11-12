# דוח מדידות ביצועים

Commit: `6aa411d774f453331d6821dbb5a68f1c3b78bd78` · מצב: profile · מטמון: cold

הרצה שלמה: true · הצלחה: true

| תרחיש | מצב | n | p50 ms | p95 ms | p99 ms | build p95 ms | raster p95 ms | RSS peak MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| startup.first_content | passed | 4 | 552.094 | 646.229 | 646.229 | 41.793 | 155.845 | 331.164 |
| startup.window_useful | passed | 4 | 255.000 | 372.000 | 372.000 | — | — | — |
| book.short.open | passed | 16 | 88.381 | 104.652 | 104.652 | 18.962 | 4.562 | 902.520 |
| book.short.scroll | passed | 16 | 937.800 | 1023.675 | 1023.675 | 2.179 | 5.696 | 652.586 |
| book.short.jump_forward | passed | 16 | 59.129 | 68.174 | 68.174 | 27.416 | 2.139 | 538.414 |
| book.short.jump_backward | passed | 16 | 55.378 | 79.046 | 79.046 | 37.729 | 2.261 | 533.770 |
| book.short.warmup_complete | passed | 16 | 0.052 | 0.076 | 0.076 | — | — | 525.332 |
| book.short.steady_scroll | passed | 16 | 932.081 | 942.005 | 942.005 | 1.688 | 4.626 | 526.078 |
| book.short.close | passed | 16 | 361.935 | 368.475 | 368.475 | 2.190 | 1.958 | 534.852 |
| book.medium.open | passed | 16 | 91.599 | 110.932 | 110.932 | 29.188 | 4.223 | 529.879 |
| book.medium.scroll | passed | 16 | 1045.675 | 1086.013 | 1086.013 | 7.831 | 6.268 | 538.664 |
| book.medium.jump_forward | passed | 16 | 67.250 | 84.652 | 84.652 | 33.358 | 1.982 | 567.531 |
| book.medium.jump_backward | passed | 16 | 57.068 | 74.251 | 74.251 | 34.128 | 1.967 | 548.098 |
| book.medium.warmup_complete | passed | 16 | 1118.682 | 1248.181 | 1248.181 | 6.922 | 5.790 | 537.652 |
| book.medium.steady_scroll | passed | 16 | 934.311 | 947.284 | 947.284 | 1.745 | 4.476 | 556.945 |
| book.medium.close | passed | 16 | 362.004 | 368.820 | 368.820 | 2.299 | 2.166 | 554.828 |
| book.long.open | passed | 16 | 157.193 | 184.286 | 184.286 | 84.548 | 4.668 | 563.852 |
| book.long.scroll | passed | 16 | 989.292 | 1201.482 | 1201.482 | 11.289 | 3.261 | 973.348 |
| book.long.jump_forward | passed | 16 | 77.530 | 94.002 | 94.002 | 43.186 | 2.971 | 987.605 |
| book.long.jump_backward | passed | 16 | 67.120 | 515.511 | 515.511 | 54.699 | 2.126 | 831.086 |
| book.long.warmup_complete | passed | 16 | 27364.587 | 27453.166 | 27453.166 | 7.275 | 5.394 | 900.934 |
| book.long.steady_scroll | passed | 16 | 933.714 | 952.127 | 952.127 | 1.649 | 4.478 | 964.277 |
| book.long.close | passed | 16 | 363.548 | 368.987 | 368.987 | 2.929 | 2.223 | 908.465 |
| windows.native_open_close | skipped | 0 | — | — | — | — | — | — |
| queues.depth | skipped | 0 | — | — | — | — | — | — |

| תרחיש | CPU ממוצע % ליבה | כיסוי CPU % | private peak MiB | heap אחרי p50 MiB | handles peak | תהליכים peak |
|---|---:|---:|---:|---:|---:|---:|
| startup.first_content | — | 0.000 | 292.598 | — | 628.000 | 1.000 |
| startup.window_useful | — | 0.000 | — | — | — | — |
| book.short.open | — | 0.000 | 770.754 | 73.882 | 616.000 | 1.000 |
| book.short.scroll | 27.494 | 53.384 | 380.980 | 81.171 | 616.000 | 1.000 |
| book.short.jump_forward | — | 0.000 | 405.680 | 74.035 | 609.000 | 1.000 |
| book.short.jump_backward | — | 0.000 | 387.582 | 73.811 | 614.000 | 1.000 |
| book.short.warmup_complete | — | 0.000 | — | 78.725 | — | — |
| book.short.steady_scroll | 27.572 | 40.216 | 378.938 | 78.241 | 615.000 | 1.000 |
| book.short.close | — | 0.000 | 393.707 | 72.736 | 611.000 | 1.000 |
| book.medium.open | — | 0.000 | 379.418 | 97.422 | 610.000 | 1.000 |
| book.medium.scroll | 32.344 | 59.970 | 404.539 | 86.082 | 614.000 | 1.000 |
| book.medium.jump_forward | — | 0.000 | 428.965 | 84.376 | 610.000 | 1.000 |
| book.medium.jump_backward | — | 0.000 | 397.180 | 83.507 | 610.000 | 1.000 |
| book.medium.warmup_complete | 61.737 | 48.978 | 397.117 | 91.894 | 614.000 | 1.000 |
| book.medium.steady_scroll | 33.977 | 49.819 | 421.133 | 97.209 | 614.000 | 1.000 |
| book.medium.close | — | 0.000 | 419.355 | 90.399 | 609.000 | 1.000 |
| book.long.open | — | 0.000 | 413.039 | 144.484 | 608.000 | 1.000 |
| book.long.scroll | 228.663 | 48.045 | 840.219 | 514.303 | 616.000 | 1.000 |
| book.long.jump_forward | — | 0.000 | 854.238 | 256.599 | 614.000 | 1.000 |
| book.long.jump_backward | — | 0.000 | 610.469 | 255.838 | 610.000 | 1.000 |
| book.long.warmup_complete | 78.303 | 98.091 | 750.297 | 449.237 | 617.000 | 1.000 |
| book.long.steady_scroll | 40.761 | 49.987 | 833.383 | 453.352 | 610.000 | 1.000 |
| book.long.close | — | 0.000 | 771.887 | 449.694 | 612.000 | 1.000 |
| windows.native_open_close | — | — | — | — | — | — |
| queues.depth | — | — | — | — | — | — |

אחוזונים: nearest-rank על דגימות מוצלחות בלבד, ללא warmup. מקף מציין מדד חסר. CPU: ‏100% = ליבה אחת; private memory הוא commit פרטי, ואינו אומדן לזיכרון native בלבד. דגימות גודל וזמן כיסוי CPU מפורטים ב-JSON.

## השוואה ל-baseline

| תרחיש | מצב | שינוי p50 | שינוי p95 | שינוי p99 |
|---|---|---:|---:|---:|---:|
| startup.first_content | compared | 5.051% | 4.172% | 4.172% |
| startup.window_useful | compared | 2.823% | 13.761% | 13.761% |
| book.short.open | compared | 3.385% | 7.121% | 7.121% |
| book.short.scroll | compared | 0.056% | -1.434% | -1.434% |
| book.short.jump_forward | compared | 2.154% | 8.455% | 8.455% |
| book.short.jump_backward | compared | 3.879% | 5.643% | 5.643% |
| book.short.warmup_complete | compared | 79.310% | -97.632% | -97.632% |
| book.short.steady_scroll | compared | 0.056% | 0.211% | 0.211% |
| book.short.close | compared | 0.847% | 0.553% | 0.553% |
| book.medium.open | compared | -10.426% | -36.809% | -36.809% |
| book.medium.scroll | compared | -7.940% | -9.709% | -9.709% |
| book.medium.jump_forward | compared | 1.163% | 0.781% | 0.781% |
| book.medium.jump_backward | compared | 8.649% | -2.688% | -2.688% |
| book.medium.warmup_complete | compared | 0.232% | 3.799% | 3.799% |
| book.medium.steady_scroll | compared | 0.047% | 0.744% | 0.744% |
| book.medium.close | compared | -0.397% | 0.219% | 0.219% |
| book.long.open | compared | -47.755% | -43.388% | -43.388% |
| book.long.scroll | compared | 2.696% | 20.361% | 20.361% |
| book.long.jump_forward | compared | -17.248% | -82.556% | -82.556% |
| book.long.jump_backward | compared | -25.365% | -5.746% | -5.746% |
| book.long.warmup_complete | compared | -5.051% | -12.838% | -12.838% |
| book.long.steady_scroll | compared | 0.050% | -1.786% | -1.786% |
| book.long.close | compared | -0.005% | 0.362% | 0.362% |
| windows.native_open_close | unavailable | — | — | — |
| queues.depth | unavailable | — | — | — |

שינוי חיובי הוא עלייה בזמן; אלה הבדלים תיאוריים, ללא קביעת מובהקות או סף CI.

## מגבלות המדידה

- p95/p99 עם מעט חזרות מתארים את המדגם בלבד; יש לבדוק את n
