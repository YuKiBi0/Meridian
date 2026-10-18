import { createApp } from 'vue'
import App from './App.vue'
import { lang, setLang } from './i18n'
import './styles.css'

setLang(lang.value)
createApp(App).mount('#app')
