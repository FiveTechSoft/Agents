const fs = require('fs');
let c = fs.readFileSync('check.js', 'utf8');
const lines = c.split(/\r?\n/);
let fixed = 0;

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("[n,t])=>n+'") {
    // Check if the next line looks like a lone close-paren-semicolon (broken join continuation)
    const next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (next === "');" || next === '");' || next === "');" || next === '");') {
      lines[i] = lines[i].replace(".join('", ".join('\\n')");
      lines.splice(i + 1, 1);
      fixed++;
    }
  }
}

fs.writeFileSync('check.js', lines.join('\r\n'));
console.log('Fixed ' + fixed + ' occurrences');
