import SwiftUI

private struct Guideline: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

private let guidelines: [Guideline] = [
    Guideline(icon: "bubbles.and.sparkles", title: "בלי משקאות מוגזים",
              detail: "הגז עלול לגרום ללחץ, נפיחות ואי-נוחות בקיבה הקטנה. כולל סודה, מים מוגזים ובירה."),
    Guideline(icon: "drop.triangle", title: "הפרדה בין שתייה לאכילה",
              detail: "לסיים לשתות כ-30 דקות לפני הארוחה ולחזור לשתות כ-30 דקות אחריה. שתייה עם האוכל תופסת מקום בקיבה ועלולה לגרום לאי-נוחות ולמעבר מהיר מדי של מזון."),
    Guideline(icon: "timer", title: "אכילה איטית",
              detail: "כ-15 דקות לארוחה עיקרית. אכילה מהירה עלולה לגרום לכאב, בחילה והקאה. להניח את הסכו״ם בין ביס לביס."),
    Guideline(icon: "mouth", title: "לעיסה נכונה",
              detail: "ביסים קטנים ולעיסה של 20–30 פעמים, עד שהמזון במרקם של מחית, לפני הבליעה."),
    Guideline(icon: "fork.knife", title: "5 ארוחות קטנות ביום",
              detail: "3 ארוחות עיקריות ו-2 ארוחות ביניים, בזמנים קבועים. להתחיל כל ארוחה מהחלבון."),
    Guideline(icon: "pills", title: "ויטמינים ומינרלים כל יום",
              detail: "אחרי מיני מעקף הספיגה של חלק מהוויטמינים והמינרלים יורדת, ולכן לוקחים תוספים לאורך זמן — לפי ההמלצה האישית. סידן וברזל בהפרדה."),
    Guideline(icon: "cup.and.saucer", title: "שתייה מספקת",
              detail: "לשתות לאורך היום בלגימות קטנות, בלי קש (קש מכניס אוויר). לשאוף ליעד השתייה שהדיאטנית קבעה."),
    Guideline(icon: "figure.walk", title: "פעילות גופנית",
              detail: "הליכה של שעה, 3 פעמים בשבוע, ובשאר הימים — כמה שיותר צעדים. להעלות עומס בהדרגה ולפי אישור הצוות."),
    Guideline(icon: "exclamationmark.triangle", title: "להיזהר ממתוקים ומשומן",
              detail: "מזונות מתוקים או שומניים עלולים לגרום לתסמונת דאמפינג: חולשה, הזעה, דופק מהיר ושלשול."),
    Guideline(icon: "wineglass", title: "אלכוהול",
              detail: "אחרי מעקף האלכוהול נספג מהר יותר. להתייעץ עם הצוות לפני שתייה של אלכוהול."),
]

struct GuidelinesView: View {
    var body: some View {
        List {
            Section {
                ForEach(guidelines) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("המידע כללי ונועד לעזור בבניית הרגלים. בכל שאלה, ובמקרה של כאב, הקאות חוזרות או חום — לפנות לצוות הרפואי.")
            }
        }
        .navigationTitle("המלצות והסברים")
    }
}
