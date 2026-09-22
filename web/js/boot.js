import('./app.js').catch((error) => {
  console.error(error);
  const root = document.getElementById('root');
  if (!root) return;
  root.replaceChildren();
  const box = document.createElement('div');
  box.style.cssText = 'max-width:28rem;margin:4rem auto;padding:1.5rem;font-family:Tahoma,sans-serif;line-height:1.8';
  const msg = String(error && error.message ? error.message : error);
  box.innerHTML =
    '<h1>داشبورد بارگذاری نشد</h1>' +
    '<p></p>' +
    '<p>یک‌بار صفحه را با Ctrl+F5 تازه کنید. اگر باز هم خالی بود، سرور را با npm start در پوشه backend از نو اجرا کنید.</p>';
  box.querySelector('p').textContent = msg;
  root.append(box);
});
