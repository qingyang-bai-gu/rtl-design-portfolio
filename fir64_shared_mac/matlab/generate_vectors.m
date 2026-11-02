function generate_vectors(out_dir)
%GENERATE_VECTORS Toolbox-free Q1.15 FIR oracle and reproducible test vectors.
% From this directory: generate_vectors('../build/matlab_vectors')
% Integer-valued double arithmetic is exact here: every sum is below 2^53.
if nargin < 1
    out_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'build', 'matlab_vectors');
end
mkdir_if_missing(fullfile(out_dir, 'coefficients'));
mkdir_if_missing(fullfile(out_dir, 'vectors'));
n = (0:63) - 31.5;
h = sin(2*pi*0.10*n) ./ (pi*n);
h = h .* (0.54 - 0.46*cos(2*pi*(0:63)/63));
c = round(h / sum(h) * 32768);
correction = 32768 - sum(c);
assert(mod(correction, 2) == 0);
c(32:33) = c(32:33) + correction/2;
assert(isequal(c, fliplr(c)) && sum(c) == 32768);

x = [zeros(1,4), 32767, zeros(1,79), -32768, zeros(1,79), ...
     32767*ones(1,96), zeros(1,80), -32768*ones(1,96), zeros(1,80), ...
     repmat([32767,-32768],1,64), ...
     repmat([1,-1,3,-3,16384,-16384,0,32767,-32768],1,8)];
state = uint32(hex2dec('13579bdf'));
random_samples = zeros(1,1024);
for k = 1:1024
    state = bitxor(state, bitshift(state,13));
    state = bitxor(state, bitshift(state,-17));
    state = bitxor(state, bitshift(state,5));
    v = double(bitand(state,uint32(65535)));
    if v >= 32768, v = v - 65536; end
    random_samples(k) = v;
end
x = [x,random_samples,zeros(1,80)];
write_hex(fullfile(out_dir,'vectors','input.hex'),x,16);
names = {'lowpass','stress','half'};
coeffs = {c,-32768*ones(1,64),[16384,zeros(1,63)]};
for p = 1:numel(names)
    taps = coeffs{p};
    % Direct convolution keeps this oracle independent of RTL RAM sequencing.
    acc = conv(x,taps);
    acc = acc(1:numel(x));
    assert(all(acc == fix(acc)) && all(abs(acc) < 2^37));
    y = sign(acc).*floor((abs(acc)+16384)/32768);
    y = min(32767,max(-32768,y));
    write_hex(fullfile(out_dir,'coefficients',[names{p},'_q15.hex']),taps,16);
    write_hex(fullfile(out_dir,'vectors',[names{p},'_acc.hex']),acc,38);
    write_hex(fullfile(out_dir,'vectors',[names{p},'_output.hex']),y,16);
end
fprintf('Generated %d samples and three coefficient profiles in %s\n',numel(x),out_dir);
end

function write_hex(path, values, bits)
fid = fopen(path,'w');
assert(fid ~= -1, ['Cannot open ',path]);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
for k = 1:numel(values)
    fprintf(fid,'%s\n',lower(dec2hex(mod(values(k),2^bits),ceil(bits/4))));
end
end

function mkdir_if_missing(path)
if ~exist(path,'dir'), mkdir(path); end
end
