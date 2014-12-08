#include "DirectForcingSolver.h"
#include <sys/stat.h>
#include <thrust/extrema.h>
#include <cusp/io/matrix_market.h>

template <typename memoryType>
DirectForcingSolver<memoryType>::DirectForcingSolver(parameterDB *pDB, domain *dInfo)
{
	NavierStokesSolver<memoryType>::paramDB = pDB;
	NavierStokesSolver<memoryType>::domInfo = dInfo;
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::initialise()
{
	int nx = NavierStokesSolver<memoryType>::domInfo->nx,
        ny = NavierStokesSolver<memoryType>::domInfo->ny;

	int numUV = (nx-1)*ny + nx*(ny-1);
	int numP  = nx*ny;
	
	NavierStokesSolver<memoryType>::initialiseCommon();
	
	NSWithBody<memoryType>::initialiseBodies();
	
	NavierStokesSolver<memoryType>::initialiseArrays(numUV, numP);
	
	NavierStokesSolver<memoryType>::logger.startTimer("allocateMemory");

	tags.resize(numUV);
	tagsD.resize(numUV);
	tags2.resize(numUV);
	tags2D.resize(numUV);
	coeffs.resize(numUV);
	coeffsD.resize(numUV);
	coeffs2.resize(numUV);
	coeffs2D.resize(numUV);
	uv.resize(numUV);
	uvD.resize(numUV);

	pressure.resize(numP);
	cusp::blas::fill(pressure, 0.0);

	NavierStokesSolver<memoryType>::logger.startTimer("allocateMemory");
	
	tagPoints();
	std::cout << "Done tagging points!" << std::endl;
	
	NavierStokesSolver<memoryType>::assembleMatrices();
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::updateSolverState()
{
	if (NSWithBody<memoryType>::B.bodiesMove)
	{
		// update the locations of the body points
		NSWithBody<memoryType>::updateBodies();
		
		// retag points
		tagPoints();
		
		// assemble the matrices generated using new tags
		NavierStokesSolver<memoryType>::assembleMatrices();
	}
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::assembleRHS1()
{
	NavierStokesSolver<memoryType>::assembleRHS1();
	
	NavierStokesSolver<memoryType>::logger.startTimer("updateRHS1");
	updateRHS1();
	NavierStokesSolver<memoryType>::logger.startTimer("updateRHS1");
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::writeMassFluxInfo()
{
	parameterDB  &db = *NavierStokesSolver<memoryType>::paramDB;
	int     nx = NavierStokesSolver<memoryType>::domInfo->nx,
	        ny = NavierStokesSolver<memoryType>::domInfo->ny,
	        timeStep = NavierStokesSolver<memoryType>::timeStep;

	cusp::array1d<real, memoryType> fluxes(nx*ny);
	cusp::multiply(NavierStokesSolver<memoryType>::QT, NavierStokesSolver<memoryType>::q, fluxes);
	int minPosition = thrust::min_element(fluxes.begin(), fluxes.end()) - fluxes.begin(),
	    maxPosition = thrust::max_element(fluxes.begin(), fluxes.end()) - fluxes.begin();
	real minFlux = fluxes[minPosition],
	     maxFlux = fluxes[maxPosition],
	     globalSum = thrust::reduce(fluxes.begin(), fluxes.end());

	std::ofstream fluxInfoFile;
	std::string folder = db["inputs"]["caseFolder"].get<std::string>();
	std::stringstream out;
	out << folder << "/massFlux";
	
	if(timeStep==1)
		fluxInfoFile.open(out.str().c_str());
	else
		fluxInfoFile.open(out.str().c_str(), std::ios::out | std::ios::app);
		
	fluxInfoFile << timeStep << '\t' << minFlux << '\t' << maxFlux << '\t' << globalSum << std::endl;
	fluxInfoFile.close();
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::projectionStep()
{
	NavierStokesSolver<memoryType>::projectionStep();

	NavierStokesSolver<memoryType>::logger.startTimer("projectionStep");
	cusp::blas::axpy(NavierStokesSolver<memoryType>::lambda, pressure , 1.0);
	NavierStokesSolver<memoryType>::logger.stopTimer("projectionStep");
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::writeData()
{	
	NavierStokesSolver<memoryType>::logger.startTimer("output");

	parameterDB  &db = *NavierStokesSolver<memoryType>::paramDB;
	real         dt  = db["simulation"]["dt"].get<real>();
	int          timeStep = NavierStokesSolver<memoryType>::timeStep;

	NSWithBody<memoryType>::writeCommon();
	
	// Print forces calculated using the CV approach
	NSWithBody<memoryType>::calculateForce();
	NSWithBody<memoryType>::forceFile << timeStep*dt << '\t' << NSWithBody<memoryType>::forceX << '\t' << NSWithBody<memoryType>::forceY << std::endl;

	writeMassFluxInfo();
	
	NavierStokesSolver<memoryType>::logger.stopTimer("output");
}

template <typename memoryType>
void DirectForcingSolver<memoryType>::generateC()
{
	int nx = NavierStokesSolver<memoryType>::domInfo->nx,
	    ny = NavierStokesSolver<memoryType>::domInfo->ny;
	int index = 5*(ny/2)*nx - nx - ny + 5*(nx/2) - 1 + 2;
	int row = (ny/2)*nx+nx/2;

	NavierStokesSolver<memoryType>::generateC();
	bool flag = true;
	while(flag)
	{
		if(NavierStokesSolver<memoryType>::C.row_indices[index]==NavierStokesSolver<memoryType>::C.column_indices[index] && NavierStokesSolver<memoryType>::C.column_indices[index]==row)
		{
			NavierStokesSolver<memoryType>::C.values[index] += NavierStokesSolver<memoryType>::C.values[index];
			flag = false;
		}
		index++;
	}
	//cusp::io::write_matrix_market_file(NavierStokesSolver<memoryType>::C, "C-generateQT.mtx");
}

#include "DirectForcing/tagPoints.inl"
#include "DirectForcing/generateL.inl"
//
#include "DirectForcing/generateA.inl"
//
#include "DirectForcing/updateRHS1.inl"
#include "DirectForcing/generateQT.inl"

template class DirectForcingSolver<host_memory>;
template class DirectForcingSolver<device_memory>;
