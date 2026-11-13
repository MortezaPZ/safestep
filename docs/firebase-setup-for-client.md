# Firebase setup for SafeStep

The application already contains the Firebase Messaging integration. To send remote push notifications, the organization that owns the deployment should create and retain the Firebase project and its server credential. The project-specific files are installed locally at deployment time and must stay out of source control and delivery archives.

## Android application configuration

Create or select a Firebase project owned by the organization, then register an Android application with the SafeStep application ID `ir.hamghadam.safestep`. Download its `google-services.json` and place it at:

```text
mobile/android/app/google-services.json
```

The Android Gradle setup applies the Google Services plugin only when this file exists. Without it, local development can still build, but Firebase Messaging is not configured. The app-specific ignore rule keeps this file out of Git and the delivery ZIP.

## Backend service credential

In the same Firebase project, enable Firebase Cloud Messaging API (HTTP v1) and create a service-account credential authorized to send FCM messages for that project. Keep the private-key JSON with the deployment operator; never add it to the repository, a ZIP, a ticket, or a public chat.

Provide the backend with one of these options:

1. **Preferred for a server/container:** mount the service-account JSON as a runtime secret and set `FCM_SERVICE_ACCOUNT_PATH` to its absolute path. For example, a container can mount it at `/run/secrets/safestep-fcm-service-account.json`.
2. **Environment value:** set `FCM_SERVICE_ACCOUNT_JSON` to the service-account JSON text or its Base64 encoding. Use the platform's secret store for this value; do not put it in a committed `.env` file.

The code reads `FCM_SERVICE_ACCOUNT_JSON` before `FCM_SERVICE_ACCOUNT_PATH`; if both are set, the JSON value takes precedence. `FCM_PROJECT_ID` is optional: when omitted, the backend reads `project_id` from the service-account JSON. When set, it overrides that value. `NOTIFICATION_DRIVER` accepts `auto`, `fcm`, or `local`; `auto` is the default and selects FCM when the credential parses successfully.

## Device verification

After installing the Android configuration, configure the backend secret and deploy the backend against the same project. Install a fresh build on a real Android phone, grant notification permission, sign in, and confirm the device token is registered. Then send a test alert and verify it while the app is foregrounded, backgrounded, and the screen is locked. A successful server response alone does not confirm that Android displayed the notification.

The fall countdown is a local notification scheduled by the app. It does not require an FCM project, but its background and lock-screen behavior still needs a real-device check. Remote caregiver alerts use FCM and require both the Android configuration file and backend service credential above.
