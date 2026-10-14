# תזונה, יעד חלבון ויומן ארוחות עם צילום — מסמך עיצוב

תאריך: 2026-10-14 · סטטוס: ממתין לאישור · ענף: `feature/nutrition-protein-photo`

## 1. מטרה

לעזור למשתמש (אחרי מיני מעקף / OAGB) להגיע ל-**100 גר' חלבון ביום**:
לדעת מה לאכול, לראות כמה נשאר, ולתעד ארוחות בצילום שמזוהה אוטומטית.

**מוכן כש:**
- בלשונית "תזונה" אפשר לצלם צלחת; תוך דקה (כשהמק זמין) מוצגת רשימת מאכלים עם גרמים וחלבון, ניתנת לעריכה, ונספרת ליעד היומי.
- כשהמק לא זמין — הצילום נשמר כ"ממתין" ומזוהה אוטומטית אחר כך, גם מחוץ לבית (Tailscale).
- במסך "היום" רואים התקדמות חלבון ו-2–3 הצעות להשלמה, מותאמות לשלב אחרי הניתוח.
- ספריית מקורות חלבון, מתכונים וכללים — כל פריט עם קישור למקור, ורק פריטים שעברו אימות.
- הנתונים הקיימים של המשתמש לא נמחקים בעדכון.

**מחוץ לתחום:** קלוריות/פחמימות/שומן, סנכרון ענן, ברקודים, אישור דיאטנית בתוך האפליקציה, הפצה ב-App Store.

## 2. החלטות שהתקבלו

| נושא | החלטה |
|---|---|
| זיהוי תמונה | Claude דרך **סשן Claude Code על המק** (מנוי המשתמש), לא מפתח API באייפון |
| טווח | מכל מקום — **Tailscale** על המק והאייפון |
| המלצות | **שילוב**: תוכן קבוע ומאומת באפליקציה + כפתור "תציע לי מתכון" דרך Claude |
| אימות תוכן | כל מספר/כלל נבדק מול מקור על ידי בודק בהקשר נפרד; נפסלים לא נכנסים |
| ניווט | לשונית חדשה **"תזונה"**; "הגדרות" עוברת לכפתור ⚙️ במסך "היום" (נשארות 5 לשוניות) |
| המק | דלוק כל הזמן; הגשר רץ כ-LaunchAgent |

## 3. ארכיטקטורה

```
iPhone (SwiftUI)                                   Mac
┌──────────────────────────┐   HTTP + Bearer   ┌──────────────────────────┐
│ NutritionView / Today    │  over Tailscale   │ bridge/server.py         │
│ AnalysisQueue ───────────┼──────────────────▶│  POST /analyze  (image)  │
│ BridgeClient             │◀──────────────────┼  POST /recipe   (text)   │
│ FoodLibrary (JSON bundle)│      JSON         │  GET  /health            │
│ ProteinCalculator        │                   │   └─ claude -p (Read only)│
│ PhotoStore (files)       │                   └──────────────────────────┘
└──────────────────────────┘
```

### 3.1 יחידות באייפון

| יחידה | אחריות | תלויות |
|---|---|---|
| `FoodEntry`, `FoodItem` (Models) | ארוחה מתועדת: זמן, slot, פריטים (שם, גרמים, חלבון), נתיב תמונה, `status` | — |
| `ProteinCalculator` | סכום חלבון ליום, נותר ליעד, הצעות מהספרייה לפי שלב ונותר | FoodLibrary |
| `FoodLibrary` | טעינת `nutrition-library.json` מה-bundle; סינון לפי `DietStage` | — |
| `DietStage` | שלב (לפני/נוזלים/מחית/רך/רגיל) מתאריך הניתוח, עם דריסה ידנית בהגדרות | AppSettings |
| `PhotoStore` | שמירה/טעינה/מחיקה של JPEG (דחוס, ≤1600px) ב-Application Support | FileManager |
| `BridgeClient` | קריאות HTTP לגשר; timeout 90s; מיפוי שגיאות לטיפוסים | URLSession |
| `AnalysisQueue` | מעבר על ארוחות `pending`, שליחה, עדכון סטטוס; רץ ב-foreground ובפתיחת "תזונה" | BridgeClient, AppStore |
| `NutritionView` + `MealCaptureView` + `MealReviewView` + `LibraryView` | ממשק | הכל למעלה |

`FoodEntry.status`: `pending` → `analyzing` → `needsReview` → `confirmed` · או `failed(reason)` · או `manual` (בלי צילום).
ארוחה נספרת ליעד רק ב-`confirmed`/`manual`. ב-`needsReview` מוצג באנר "יש ארוחה לאישור".

### 3.2 שינויי נתונים — **ללא אובדן מידע**

היום `AppStore` עושה `try? JSONDecoder().decode(AppState.self ...)` — שדה חדש לא-אופציונלי ישבור את הפענוח
**ויאפס את כל המידע של המשתמש**. לכן:
- `DayLog`, `AppState`, `AppSettings` מקבלים `init(from:)` מותאם עם `decodeIfPresent` לכל שדה.
- שדות חדשים: `DayLog.foodEntries: [FoodEntry]`, `AppSettings.proteinGoalGrams = 100`,
  `AppSettings.dietStageOverride: DietStage?`, `AppSettings.bridgeURL: String?`.
- הטוקן נשמר ב-**Keychain**, לא ב-JSON.
- טסט: פענוח JSON בפורמט הישן מצליח ושומר את כל הערכים.

### 3.3 הגשר על המק (`bridge/`)

- `server.py` — Python 3 stdlib בלבד (`http.server`, `ThreadingHTTPServer`), מאזין ל-`0.0.0.0:8787`.
- כל בקשה דורשת `Authorization: Bearer <token>`; השוואה ב-`hmac.compare_digest`. בלי טוקן → 401.
- מגבלות: תמונה ≤ 8MB, בקשה אחת במקביל ל-`claude` (תור פנימי), timeout 120s לתהליך.
- `/analyze`: שומר את התמונה לקובץ זמני, מריץ
  `claude -p "<prompt>" --output-format json --allowedTools Read` עם נתיב הקובץ, מוחק את הקובץ בסיום.
  ה-prompt קבוע בקוד ודורש JSON בסכמה:
  `{"items":[{"name":"…","grams":0,"protein_g":0,"confidence":"low|medium|high"}],"notes":"…"}`.
  השרת מאמת את הסכמה לפני ההחזרה; כשלון → 502 עם קוד `BAD_MODEL_OUTPUT`.
- `/recipe`: גוף `{remaining_g, stage, have:[…]}` → מתכון אחד בסכמה קבועה, מסומן באפליקציה "הצעת AI — לא נבדק".
- `/health`: `{status:"ok", claude:true|false}`.
- `install.sh`: יוצר טוקן אקראי (32 bytes) ב-`~/.config/bariatric-bridge/token` (הרשאות 600),
  מתקין LaunchAgent, ומדפיס QR/טקסט עם כתובת Tailscale + טוקן להזנה באייפון.
- לוגים ל-`~/Library/Logs/bariatric-bridge.log` — בלי תמונות ובלי הטוקן.

### 3.4 רשת ואבטחה

- הגשר לא נחשף לאינטרנט; נגיש רק ב-LAN/Tailscale (WireGuard מצפין את התעבורה).
- ATS: `NSAllowsLocalNetworking` + בדיקה על המכשיר שחיבור ל-IP של Tailscale (`100.x.y.z`) עובר.
  אם לא — חריגה ספציפית לדומיין ה-MagicDNS של ה-tailnet.
- `NSLocalNetworkUsageDescription` ו-`NSCameraUsageDescription` בעברית.
- Claude רץ עם `Read` בלבד — טקסט בתוך תמונה לא יכול להפעיל פעולות על המק.

## 4. תוכן — ספריית תזונה

קובץ `BariatricHabits/Resources/nutrition-library.json`:
- `proteinSources[]`: `nameHe`, `servingText`, `servingGrams`, `proteinPerServing`, `proteinPer100g`, `stages[]`, `toleranceNote`, `sourceURL`, `verified`.
- `recipes[]`: `nameHe`, `ingredients[]`, `steps[]`, `proteinPerPortion`, `portions`, `stage`, `warnings[]`, `sourceURL`, `verified`.
- `rules[]`: `textHe`, `sourceURL`.

**מקורות — אומתו (41/41 נבדקו, 40 אושרו, 1 עם תיקון ניסוח, 0 נפסלו):** ראו
[`docs/research/2026-10-14-nutrition-sources.md`](../../research/2026-10-14-nutrition-sources.md) — זה מקור האמת לנתוני ה-JSON.

**תיקונים מחייבים מהאימות:**
- **מנות ריאליות:** `servingGrams` לפי שלב — מחית/רך: 60–100 גר', רגיל: עד 150 גר'. לא "גביע 250 גר'".
- **"גלידת חלבון" (בננה)** ו**לביבות גבינה (קמח + סוכר)**: רק בשלב רגיל, עם אזהרת דאמפינג/פחמימות.
- **חלבון ביצה** — "מבושל" בלבד (ערך USDA הוא לחלבון נא).
- **לבנה** — בלי שם מותג (הרשומה ב-OFF היא Karoun 9%).
- **שומן גבוה** (סרדינים בשמן, טחינה, עוגת גבינה, קציצות בשמן זית) — הערת "מנה קטנה; שומן עלול להחמיר שלשולים".
- **בשר אדום וקטניות** — רק בשלב רגיל, עם הערת סבילות.
- **לקטוז** — כלל כללי: "אם יש אי-סבילות — מוצרים ללא לקטוז / Whey isolate".
- ציטוט ERAS ישירות: Stenberg et al. 2022; כלל קולגן: "לא מומלץ"; Whey isolate: "אפשרות", לא "מומלץ".
- כלל "חצי מהארוחה חלבון" — לשלבי מחית ורך בלבד.
- כלל הסוכר מנוסח במקור ל-RYGB; מוצג כ"אחרי מעקף".

**כללי הכללה:**
- רק פריטים עם verdict `CONFIRMED`/`CORRECTED` מהבודק נכנסים; `REJECTED`/`UNVERIFIABLE` מדווחים למשתמש.
- פריטים עם סוכר מוסף (סיכון דאמפינג) נכנסים רק עם אזהרה, או לא נכנסים.
- הודעה קבועה: "המידע כללי, נבדק מול מקורות, ואינו מחליף את הדיאטנית".

**הצעות במסך "היום":** אם נותרו X גר' — עד 3 פריטים מהשלב הנוכחי שה-`proteinPerServing` שלהם הכי קרוב ל-min(X, 30),
עם עדיפות לפריטים שלא נאכלו היום.

## 5. טיפול בשגיאות

| מצב | התנהגות |
|---|---|
| המק לא זמין / timeout | הארוחה נשארת `pending`, ניסיון חוזר בפתיחה הבאה; אין alert |
| 401 | `failed(.unauthorized)` + הודעה בהגדרות "הטוקן שגוי" |
| `BAD_MODEL_OUTPUT` | `failed(.unreadable)` + כפתור "הזנה ידנית" |
| התמונה נמחקה מהדיסק | `failed(.missingPhoto)`; אפשר להזין ידנית |
| Claude לא מחובר על המק | `/health` מחזיר `claude:false` → הודעה "יש להתחבר ל-Claude על המק" |

## 6. טסטים

- **Swift (XCTest, target חדש `BariatricHabitsTests`):** ProteinCalculator (סכום, נותר, הצעות), DietStage (גבולות ימים + דריסה),
  פענוח תשובת הגשר (תקין/חסר שדות/זבל), מעברי סטטוס ב-AnalysisQueue עם BridgeClient מזויף, מיגרציית JSON ישן.
- **Python (`unittest`):** טוקן חסר/שגוי/תקין, מגבלת גודל, אימות סכמה, `claude` מזויף (סקריפט שמחזיר JSON קבוע / זבל / נתקע).
- **ידני:** צילום צלחת אמיתית מהאייפון דרך Tailscale מחוץ לרשת הביתית; מצב טיסה → pending → חזרה → זיהוי.

## 7. סיכונים

- **דיוק הערכת כמות מתמונה נמוך** — לכן מסך אישור/עריכה חובה, ו-`confidence` מוצג.
- **מכסת המנוי** — כל צילום הוא קריאה ל-Claude; אין ניסיונות חוזרים אוטומטיים על `BAD_MODEL_OUTPUT`.
- **תוכן רפואי** — יעדים ושלבים משתנים בין תוכניות; הכל ניתן לשינוי בהגדרות ומסומן כמידע כללי.
