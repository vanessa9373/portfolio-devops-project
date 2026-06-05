// Navbar scroll
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.style.borderBottomColor = window.scrollY > 40
    ? 'rgba(139,92,246,0.25)'
    : 'rgba(139,92,246,0.12)';
});

// Back to top
const backToTop = document.getElementById('backToTop');
window.addEventListener('scroll', () => {
  backToTop.classList.toggle('visible', window.scrollY > 400);
});
backToTop.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));

// SA project filter
document.querySelectorAll('[data-filter]').forEach(btn => {
  btn.addEventListener('click', () => {
    btn.closest('.filter-row').querySelectorAll('[data-filter]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.filter;
    document.querySelectorAll('#sa-grid .proj-card').forEach(card => {
      const tags = card.dataset.tags || '';
      card.classList.toggle('hidden', filter !== 'all' && !tags.includes(filter));
    });
  });
});

// SRE filter
document.querySelectorAll('[data-sre-filter]').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('[data-sre-filter]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.sreFilter;
    document.querySelectorAll('#sre-grid .sre-card').forEach(card => {
      const tags = card.dataset.sreTags || '';
      card.classList.toggle('hidden', filter !== 'all' && !tags.includes(filter));
    });
  });
});
