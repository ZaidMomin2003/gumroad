import { initializeApp } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-app.js";
import { getFirestore, collection, addDoc, serverTimestamp } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-firestore.js";

const firebaseConfig = {
    apiKey: "AIzaSyBR8Y1Q_8dD1Spfscii0EN_N5xcmRzmtn4",
    authDomain: "cleanmails-8efa5.firebaseapp.com",
    projectId: "cleanmails-8efa5",
    storageBucket: "cleanmails-8efa5.firebasestorage.app",
    messagingSenderId: "203900319955",
    appId: "1:203900319955:web:ae966f7899dc83dcc03c26"
};

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export { collection, addDoc, serverTimestamp };
