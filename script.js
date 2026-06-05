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
document.querySelectorAll('[data-sa-filter]').forEach(btn => {
  btn.addEventListener('click', () => {
    btn.closest('.filter-row').querySelectorAll('[data-sa-filter]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.saFilter;
    document.querySelectorAll('#sa-grid .proj-card').forEach(card => {
      const tags = card.dataset.tags || '';
      card.classList.toggle('hidden', filter !== 'all' && !tags.includes(filter));
    });
  });
});

// Lab filter
document.querySelectorAll('.lab-filter').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.lab-filter').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.labFilter;
    document.querySelectorAll('#labs-grid .lab-card').forEach(card => {
      const tags = card.dataset.labTags || '';
      card.classList.toggle('hidden', filter !== 'all' && !tags.includes(filter));
    });
  });
});

// ROI Calculator
function calculateROI() {
  const spend     = parseFloat(document.getElementById('currentSpend').value) || 0;
  const downtime  = parseFloat(document.getElementById('downtimeHours').value) || 0;
  const revenue   = parseFloat(document.getElementById('revenuePerHour').value) || 0;
  const workload  = document.getElementById('workloadType').value;

  const savings = { general: 0.22, serverless: 0.45, kubernetes: 0.28, data: 0.32 };
  const savingsPct = savings[workload] || 0.22;

  const monthlySavings     = spend * savingsPct;
  const annualSavings      = monthlySavings * 12;
  const downtimeCost       = downtime * revenue;
  const optimizedDowntime  = downtimeCost * 0.85;
  const totalAnnualValue   = annualSavings + (optimizedDowntime * 12);

  const fmt = (n) => '$' + Math.round(n).toLocaleString();
  const pct = Math.round(savingsPct * 100);

  document.getElementById('roi-results').innerHTML = `
    <div class="roi-output">
      <div class="roi-output-title">Estimated Annual Value</div>
      <div class="roi-item">
        <span class="roi-item-label">Current monthly spend</span>
        <span class="roi-item-value negative">${fmt(spend)}/mo</span>
      </div>
      <div class="roi-item">
        <span class="roi-item-label">Estimated cost reduction (${pct}%)</span>
        <span class="roi-item-value">${fmt(monthlySavings)}/mo saved</span>
      </div>
      <div class="roi-item">
        <span class="roi-item-label">Current downtime cost</span>
        <span class="roi-item-value negative">${fmt(downtimeCost)}/mo</span>
      </div>
      <div class="roi-item">
        <span class="roi-item-label">Downtime reduction (85%)</span>
        <span class="roi-item-value">${fmt(optimizedDowntime)}/mo recovered</span>
      </div>
      <div class="roi-total">
        <div class="roi-total-label">Total Estimated Annual Value</div>
        <div class="roi-total-value">${fmt(totalAnnualValue)}</div>
      </div>
      <p class="roi-note">Estimates based on typical AWS optimization benchmarks. Actual results vary by workload.</p>
    </div>`;
}
