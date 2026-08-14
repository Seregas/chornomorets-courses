// Підвантажує server/.env у process.env ДО того, як інші модулі прочитають змінні.
// Імпортується найпершим у index.ts. Node ≥20.12 має process.loadEnvFile().
const loadEnvFile = (process as unknown as { loadEnvFile?: (path?: string) => void })
  .loadEnvFile;
try {
  loadEnvFile?.(); // читає ./.env відносно cwd (server/), якщо файл є
} catch {
  // .env відсутній — це нормально, змінні можна задати й через оточення
}
