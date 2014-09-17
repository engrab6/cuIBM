#!/usr/bin/env python

# file: $CUIBM_DIR/scripts/python/readData.py
# author: Anush Krishnan (anush@bu.edu), Olivier Mesnard (mesnardo@gwu.edu)
# description: definitions of functions to read numerical data


import argparse

import numpy as np


def readSimulationParameters(folder):
	"""Reads the parameters of the simulation.
	
	Arguments
	---------
	folder -- path of the simulation case.

	Returns
	-------
	nt -- total number of time-steps.
	start_step -- initial time-step.
	nsave -- saving interval.
	dt -- time-increment.
	"""
	# open and read the info file
	with open(folder+'/run.info', 'r') as infile:
		option_list = infile.read().split()
	
	# create the parser
	parser = argparse.ArgumentParser()
	# fill the parser with arguments
	parser.add_argument('--nx', dest='nx', type=int,
						help='number of cells in the x-direction')
	parser.add_argument('--ny', dest='ny', type=int,
						help='number of cells in the y-direction')
	parser.add_argument('--nt', dest='nt', type=int,
						help='total number of time-steps')
	parser.add_argument('--nsave', dest='nsave', type=int,
						help='saving interval')
	parser.add_argument('--startStep', dest='start_step', type=int,
						help='starting time-step')
	parser.add_argument('--dt', dest='dt', type=float,
						help='time-increment')
	parser.add_argument('--vortlim', dest='vort_lim', type=float,
						help='vorticity limit')
	parser.add_argument('--folder', dest='folder_name', type=str,
						help='name of the folder in which data is saved')
	parser.add_argument('--nu', dest='nu', type=float,
						help='kinematic viscosity')
	parser.add_argument('--input', dest='body_file', type=str,
						help='body input file')
	parser.add_argument('--flowFile', dest='flow_file', type=str,
						help='flow description file')
	parser.add_argument('--domainFile', dest='domain_file', type=str,
						help='mesh description file')
	parser.add_argument('--simulation_file', dest='simulation_file', type=str,
						help='simulation parameters file')
	parser.add_argument('--bodyFile', dest='body_file', type=str,
						help='body file')
	# parse the list
	args = parser.parse_args(option_list)

	return args.nt, args.start_step, args.nsave, args.dt


def readGridData(folder):
	"""Generates the computational mesh reading the coordinates file.
	
	Arguments
	---------
	folder -- path the of simulation case.

	Returns
	-------
	nx, ny -- number of cells in the x- and y- directions.
	dx, dy -- cell widths in the x- and y- directions.
	xu, yu -- location of u-velocity points.
	xv, yv -- location of v-velocity points.
	"""
	# read the grid file
	with open(folder+'/grid', 'r') as infile:
		data = infile.readlines()

	# x-direction
	nx = int(data[0])
	x = np.array(data[1:nx+2], dtype=float)
	dx = x[1:] - x[:-1]
	xu = x[1:-1]
	xv = 0.5*(x[1:]+x[:-1])
	
	# y-direction
	ny = int(data[nx+3])
	y = np.array(data[nx+4:], dtype=float)
	dy = y[1:] - y[:-1]
	yu = 0.5*(y[1:]+y[:-1])
	yv = y[1:-1]

	return nx, ny, dx, dy, xu, yu, xv, yv


def readVelocityData(folder, time_step, nx, ny, dx, dy):
	"""Reads the velocity data at a given time-step.
	
	Arguments
	---------
	folder -- path of the simulation case.
	time-step -- current time-step.
	nx, ny -- number of cells on the x- and y- directions.
	dx, dy -- cell widths in the x- and y- directions.
	"""
	flux_file = '%s/%07d/q' % (folder, time_step)
	with open(flux_file, 'r') as infile:
		nq = int(infile.readline())			# length of flux vector q
		q = np.loadtxt(infile, dtype=float)	# store flux vector q
	
	# store u-velocities
	n_u = (nx-1) * ny				# number of u-velocity points
	u = np.empty(n_u, dtype=float)
	for j in xrange(ny):
		for i in xrange(nx-1):
			u[j*(nx-1)+i] = q[j*(nx-1)+i]/dy[j]

	# store v-velocities
	v = np.empty(nx*(ny-1), dtype=float)
	for j in xrange(ny-1):
		for i in xrange(nx):
			v[j*nx+i] = q[n_u+j*nx+i]/dx[i]
	
	return u, v