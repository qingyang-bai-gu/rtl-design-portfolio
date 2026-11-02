function analyze_filter(out_dir)
%ANALYZE_FILTER Plot quantized response and fixed-point error without toolboxes.
if nargin < 1, out_dir = fullfile('..','build','matlab_analysis'); end
if ~exist(out_dir,'dir'), mkdir(out_dir); end
generate_vectors(out_dir);
c = read_signed_hex(fullfile(out_dir,'coefficients','lowpass_q15.hex'),16);
x = read_signed_hex(fullfile(out_dir,'vectors','input.hex'),16);
y = read_signed_hex(fullfile(out_dir,'vectors','lowpass_output.hex'),16);
h = c/32768;
response = fft(h,8192);
f = (0:4096)/8192;
figure('Visible','off');
subplot(2,1,1);
plot(f,20*log10(max(abs(response(1:4097)),1e-8)));
grid on; xlabel('Frequency (cycles/sample)'); ylabel('Magnitude (dB)');
title('64-tap Hamming lowpass, quantized Q1.15 coefficients');
subplot(2,1,2); stem(0:63,h,'.'); grid on;
xlabel('Tap'); ylabel('Coefficient');
saveas(gcf,fullfile(out_dir,'filter_response.png')); close(gcf);
ideal = filter(h,1,x/32768);
error = y/32768 - ideal;
fprintf('DC gain %.8f; group delay 31.5 samples\n',sum(h));
fprintf('Fixed-point RMS error (includes clipping): %.8g\n',sqrt(mean(error.^2)));
end

function values = read_signed_hex(path,bits)
fid = fopen(path,'r'); assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
words = textscan(fid,'%s'); values = hex2dec(words{1});
values(values >= 2^(bits-1)) = values(values >= 2^(bits-1)) - 2^bits;
end
