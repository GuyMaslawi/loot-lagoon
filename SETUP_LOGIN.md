# הפעלת התחברות Google — מדריך חד-פעמי (5 דקות)

ההתחברות עם Google בנויה ומוכנה בקוד (OAuth 2.0 מלא עם PKCE). כדי להפעיל אותה צריך רק ליצור "Client ID" בחשבון Google שלך:

## שלבים

1. היכנס אל https://console.cloud.google.com/ (עם חשבון Google שלך)
2. צור פרויקט חדש (למשל "Coin Village")
3. בתפריט: **APIs & Services → OAuth consent screen**
   - בחר **External**, מלא שם אפליקציה ("Coin Village") ואימייל, שמור
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   - Application type: **Desktop app** (או **iOS**) — *לא* "Web application"
   - שם: "Coin Village Desktop"
5. העתק את ה-**Client ID** בלבד
6. צור קובץ בשם `google_oauth.json` בתיקיית הפרויקט (ליד `project.godot`) עם התוכן:

```json
{
  "client_id": "XXXXXX.apps.googleusercontent.com"
}
```

> **אל תוסיף `client_secret` לקובץ הזה.** הזרימה בקוד היא PKCE בלבד
> (`scripts/google_auth.gd`) — היא לא קוראת סוד ולא צריכה אחד. כל דבר שנמצא
> בקובץ הזה נארז לתוך האפליקציה ולכן ניתן לקריאה על ידי כל אחד, אז סוד ששמים
> כאן הוא סוד שדלף. זו גם הסיבה שסוג הקליינט חייב להיות Desktop/iOS ולא
> "Web application", שדורש סוד.

זהו! מהרגע הזה כפתור "Sign in with Google" יפתח את הדפדפן, תתחבר, והשם שלך יופיע במשחק ובטבלת הדירוג.

## Facebook

התחברות פייסבוק דורשת יצירת אפליקציה ב-https://developers.facebook.com + תהליך אישור של Meta.
מומלץ להתחיל עם Google (פשוט יותר) — נוסיף פייסבוק כשנתקרב להשקה אמיתית.

## סנכרון בענן (בהמשך)

כרגע ההתקדמות נשמרת מקומית. כדי שההתקדמות תישמר בחשבון ותעבור בין מכשירים,
נצטרך backend (מומלץ: Firebase — חינמי לרוב השימושים). זה השלב הבא אחרי שההתחברות עובדת.
