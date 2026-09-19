import os
import re
import shutil
import subprocess
import shlex
import logging
import random
import string
from string import Template
import sys

import riscof.utils as utils
import riscof.constants as constants
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

class spike(pluginTemplate):
    __model__ = "spike"

    #TODO: please update the below to indicate family, version, etc of your DUT.
    __version__ = "XXX"

    def __init__(self, *args, **kwargs):
        sclass = super().__init__(*args, **kwargs)

        config = kwargs.get('config')

        self.ref_exe = os.path.join(config['PATH'] if 'PATH' in config else "","spike")
        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        self.pluginpath=os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec']) if 'ispec' in config else ''
        self.platform_spec = os.path.abspath(config['pspec']) if 'ispec' in config else ''
        self.make = config['make'] if 'make' in config else 'make'
        logger.debug("spike plugin initialised using the following configuration.")
        for entry in config:
            logger.debug(entry+' : '+config[entry])
        return sclass

    def initialise(self, suite, work_dir, archtest_env):
        self.suite = suite
        if shutil.which(self.ref_exe) is None:
            logger.error('Please install Executable for DUTNAME to proceed further')
            raise SystemExit(1)
        self.work_dir = work_dir

        self.objdump_cmd = 'riscv64-unknown-elf-objdump -D {0} > {1};'
        self.compile_cmd = 'riscv64-unknown-elf-gcc -march={0} -mabi=ilp32 -DXLEN=32 \
         -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g\
         -T '+self.pluginpath+'/env/link.ld\
         -I '+self.pluginpath+'/env/\
         -I ' + archtest_env

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.xlen = '32'
        self.isa = 'rv32imc_zifencei'

    def runTests(self, testList, cgf_file=None):
        if os.path.exists(self.work_dir+ "/Makefile." + self.name[:-1]):
            os.remove(self.work_dir+ "/Makefile." + self.name[:-1])
        make = utils.makeUtil(makefilePath=os.path.join(self.work_dir, "Makefile." + self.name[:-1]))
        make.makeCommand = self.make + ' -j' + self.num_jobs
        for file in testList:
            testentry = testList[file]
            test = testentry['test_path']
            test_dir = testentry['work_dir']
            test_name = test.rsplit('/',1)[1][:-2]

            elf = 'ref.elf'

            execute = "@cd "+testentry['work_dir']+";"

            march = 'rv32im_zifencei'
            cmd = self.compile_cmd.format(march) + ' ' + test + ' -o ' + elf
            compile_cmd = cmd + ' -D' + " -D".join(testentry['macros'])
            execute += compile_cmd + ";"

            execute += self.objdump_cmd.format(elf, 'ref.disass')
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

            execute += f'{self.ref_exe} --isa=rv32imc_zifencei +signature={sig_file} +signature-granularity=4 {elf};'

            #TODO: The following is useful only if your reference model can
            #      support coverage extraction from riscv-isac. Else leave it
            #      commented out

            #cov_str = ' '
            #for label in testentry['coverage_labels']:
            #    cov_str+=' -l '+label
            #if cgf_file is not None:
            #    coverage_cmd = 'riscv_isac --verbose info coverage -d \
            #            -t {0}.log --parser-name c_sail -o coverage.rpt  \
            #            --sig-label begin_signature  end_signature \
            #            --test-label rvtest_code_begin rvtest_code_end \
            #            -e {0}.elf -c {1} -x{2} {3};'.format(\
            #            test_name, ' -c '.join(cgf_file), self.xlen, cov_str)
            #else:
            #    coverage_cmd = ''
            #execute+=coverage_cmd

            make.add_target(execute)
        make.execute_all(self.work_dir)
